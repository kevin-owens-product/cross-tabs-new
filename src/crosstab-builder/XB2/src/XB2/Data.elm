module XB2.Data exposing
    ( AudienceData
    , AudienceDefinition(..)
    , BaseAudienceData
    , CrosstabUser
    , DoNotShowAgain(..)
    , Shared(..)
    , SharedError(..)
    , Sharee(..)
    , Sharer
    , SharingEmail(..)
    , XBFolder
    , XBFolderId
    , XBFolderIdTag
    , XBProject
    , XBProjectData
    , XBProjectError(..)
    , XBProjectFullyLoaded
    , XBProjectHeaderSize
    , XBProjectId
    , XBProjectIdTag
    , XBProjectMetadata
    , XBUserSettings
    , canShow
    , createXBFolder
    , createXBProject
    , defaultMetadata
    , defaultMetrics
    , defaultProjectHeaderSize
    , definitionNamespaceAndQuestionCodes
    , definitionNamespaceCodes
    , destroyXBFolder
    , destroyXBFolderWithContent
    , destroyXBProject
    , destroyXBProjectTask
    , encodeAudienceDefinition
    , fetchTaskXBProjectFullyLoaded
    , fetchXBFolders
    , fetchXBProject
    , fetchXBProjectList
    , fetchXBUserSettings
    , fullUserEmailToValidSharingEmail
    , fullyLoadedToProject
    , getFullyLoadedProject
    , getProjectDatasetNames
    , getProjectQuestionCodes
    , getValidEmailCrosstabUser
    , getValidFullUserEmail
    , isMine
    , isOrgSharee
    , isSharedByMeWithOrg
    , isSharedWithMe
    , isSharedWithMyOrg
    , isUncheckedSharingEmail
    , patchXBProject
    , patchXBProjectTask
    , projectDataNamespaceCodes
    , projectIcon
    , projectOwner
    , renameXBFolder
    , shareXBProjectWithLink
    , unshareMe
    , unshareMeTask
    , unwrapSharingEmail
    , updateXBProject
    , updateXBUserSettings
    , userShareeEmail
    , validateUserEmail
    , validateUserEmailWithoutErrorDecoding
    , xbProjectErrorDisplay
    , xbProjectErrorToHttpError
    , xbUserSettingsDecoder
    )

{-| Module holding relevant XB2 data and its related functions.

TODO: This has too many responsibilities, split module into its types/functions

-}

import BiDict.Assoc as BiDict exposing (BiDict)
import Dict.Any
import Html
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as Decode
import Json.Encode as Encode exposing (Value)
import List.Extra exposing (unique)
import List.NonEmpty as NonemptyList exposing (NonEmpty)
import Maybe.Extra as Maybe
import RemoteData exposing (RemoteData(..), WebData)
import Set.Any
import Task exposing (Task)
import Time exposing (Posix)
import Url.Builder
import XB2.Data.Audience.Expression as Expression exposing (Expression)
import XB2.Data.Average as Average exposing (Average, AverageTimeFormat)
import XB2.Data.Metric as Metric exposing (Metric)
import XB2.Data.MetricsTransposition as MetricsTransposition exposing (MetricsTransposition(..))
import XB2.Data.Namespace as Namespace
import XB2.Data.Zod.Optional as Optional
import XB2.List.Sort exposing (ProjectOwner(..))
import XB2.Share.Config exposing (Flags)
import XB2.Share.Config.Main
import XB2.Share.Data.Auth as Auth
import XB2.Share.Data.Core.Error as CoreError
import XB2.Share.Data.Id exposing (Id)
import XB2.Share.Data.Labels
    exposing
        ( LocationCode
        , NamespaceAndQuestionCode
        , WaveCode
        )
import XB2.Share.Data.Platform2 exposing (DatasetCode, DatasetCodeTag, FullUserEmail, OrganisationId)
import XB2.Share.Dialog.ErrorDisplay exposing (ErrorDisplay)
import XB2.Share.Gwi.Http exposing (HttpCmd)
import XB2.Share.Gwi.Json.Decode as Decode exposing (intToString)
import XB2.Share.Gwi.Json.Encode as Encode
import XB2.Share.Gwi.List as List
import XB2.Share.Icons exposing (IconData)
import XB2.Share.Icons.Platform2 as P2Icons
import XB2.Share.Store.Platform2 exposing (Store)
import XB2.Sort as Sort exposing (Sort)



-- Adapter


{-| A function to get the proper API host based on the `State` (development, staging,
production).

TODO: Extract this into some helper module. It is duplicated in too many parts of the
codebase.

-}
host : Flags -> String
host =
    .env >> XB2.Share.Config.Main.get >> .uri >> .api


{-| TODO: This is not attached into a type? Seems fishy...
-}
namespaceNoLeadingSlash : String
namespaceNoLeadingSlash =
    "v2/saved/crosstabs"


{-| TODO: Move this into its own module or related to `Crosstab` type.
-}
type XBProjectError
    = InvalidUUID
    | DifferentOwner
    | OwnershipChangeNotAllowed
    | UniqueConstraint
    | BadShareeNotProfessional CrosstabUser
    | BadSharee
        { id : String
        , email : String
        , errorMessage : String
        , errorType : String
        }


type XBProjectIdTag
    = XBProjectIdTag


{-| TODO: Use `UUID` for this instead of `String`.
-}
type alias XBProjectId =
    Id XBProjectIdTag


{-| TODO: Move this into its own module or related to `Audience` type.
-}
type AudienceDefinition
    = Expression Expression
    | Average Average


{-| TODO: Move this into its own module or related to `Audience` type.
-}
audienceDefinitionDecoder : Decoder AudienceDefinition
audienceDefinitionDecoder =
    Decode.oneOf
        [ Decode.map Average <| Decode.field "avg" Average.decoder
        , {- expression is always present in the BE response, even if we have an
             average row/column. So we have to check presence of "avg" first to
             properly determine whether this is average or expression row/column.
          -}
          Decode.map Expression <| Decode.field "expression" Expression.decoder
        ]


{-| TODO: Move this into its own module or related to `Audience` type.
-}
encodeAudienceDefinition : AudienceDefinition -> ( String, Value )
encodeAudienceDefinition definition =
    case definition of
        Expression expr ->
            ( "expression", Expression.encode expr )

        Average average ->
            ( "avg", Average.encode average )


{-| TODO: Move this into its own module or related to `Audience` type.
-}
type alias AudienceData =
    { id : String -- the String part of AudienceItemId
    , name : String
    , fullName : String
    , subtitle : String
    , definition : AudienceDefinition
    }


{-| TODO: Move this into its own module or related to `Audience` type.
-}
type alias BaseAudienceData =
    { id : String -- the String part of AudienceItemId
    , name : String
    , fullName : String
    , subtitle : String
    , expression : Expression
    }


{-| TODO: Move this into its own module or related to `Audience` type.
-}
audienceDataDecoder : Decoder AudienceData
audienceDataDecoder =
    let
        decodeSubtitle =
            -- For now is subtitle for base audience missing
            Decode.oneOf
                [ Decode.field "subtitle" Decode.string
                , Decode.succeed ""
                ]

        fullNameDecoder =
            Decode.oneOf
                [ Decode.field "full_name" Decode.string
                , Decode.field "name" Decode.string
                ]
    in
    Decode.succeed AudienceData
        |> Decode.andMap (Decode.field "id" Decode.string)
        |> Decode.andMap (Decode.field "name" Decode.string)
        |> Decode.andMap fullNameDecoder
        |> Decode.andMap decodeSubtitle
        |> Decode.andMap audienceDefinitionDecoder


{-| TODO: Move this into its own module or related to `Audience` type.
-}
baseAudienceDataDecoder : Decoder BaseAudienceData
baseAudienceDataDecoder =
    let
        decodeSubtitle =
            -- For now is subtitle for base audience missing
            Decode.oneOf
                [ Decode.field "subtitle" Decode.string
                , Decode.succeed ""
                ]

        fullNameDecoder =
            Decode.oneOf
                [ Decode.field "full_name" Decode.string
                , Decode.field "name" Decode.string
                ]
    in
    Decode.succeed BaseAudienceData
        |> Decode.andMap (Decode.field "id" Decode.string)
        |> Decode.andMap (Decode.field "name" Decode.string)
        |> Decode.andMap fullNameDecoder
        |> Decode.andMap decodeSubtitle
        |> Decode.andMap (Decode.field "expression" Expression.decoder)


{-| TODO: Move this into its own module or related to `Audience` type.
-}
audienceDataEncode : AudienceData -> Value
audienceDataEncode { id, name, fullName, subtitle, definition } =
    Encode.object
        [ ( "id", Encode.string id )
        , ( "name", Encode.string name )
        , ( "full_name", Encode.string fullName )
        , ( "subtitle", Encode.string subtitle )
        , encodeAudienceDefinition definition
        ]


{-| TODO: Move this into its own module or related to `Audience` type.
-}
baseAudienceDataEncode : BaseAudienceData -> Value
baseAudienceDataEncode { id, name, fullName, subtitle, expression } =
    Encode.object
        [ ( "id", Encode.string id )
        , ( "name", Encode.string name )
        , ( "full_name", Encode.string fullName )
        , ( "subtitle", Encode.string subtitle )
        , ( "expression", Expression.encode expression )
        ]


{-| TODO: If it's an identifier then it should be a custom type of some sort.
-}
sharingByLinkApiIdentifier : String
sharingByLinkApiIdentifier =
    "linkSharedByURL"


{-| TODO: Move this into its own module or related to `Crosstab` type.
-}
type alias CrosstabUser =
    { id : String, email : String }


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
type Sharee
    = UserSharee CrosstabUser
    | OrgSharee OrganisationId


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
type alias Sharer =
    { id : String, email : Maybe String }


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
type Shared
    = MyPrivateCrosstab
    | MySharedCrosstab (NonEmpty Sharee)
    | SharedBy Sharer (NonEmpty Sharee)
    | SharedByLink


{-| TODO: Move this into its own module or related to `Settings` type.
-}
type DoNotShowAgain
    = DeleteRowsColumnsModal
    | DeleteBasesModal


{-| TODO: Move this into its own module or related to `Settings` type.
-}
type alias XBUserSettings =
    { canShowSharedProjectWarning : Bool
    , xb2ListFTUESeen : Bool
    , doNotShowAgain : List DoNotShowAgain
    , renamingCellsOnboardingSeen : Bool
    , freezeRowsColumnsOnboardingSeen : Bool
    , unfreezeTheFilters : Bool
    , showDetailTableInDebugMode : Bool
    , pinDebugOptions : Bool
    , editAttributeExpressionOnboardingSeen : Bool
    }


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
type alias XBProjectHeaderSize =
    { rowWidth : Int, columnHeight : Int }


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
type alias XBProjectMetadata =
    { activeMetrics : List Metric
    , averageTimeFormat : AverageTimeFormat
    , metricsTransposition : MetricsTransposition
    , sort : Sort
    , headerSize : XBProjectHeaderSize
    , frozenRowsAndColumns : ( Int, Int )
    , minimumSampleSize : Optional.Optional Int
    }


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
type alias XBProjectData =
    { ownerId : String
    , rows : List AudienceData
    , columns : List AudienceData
    , locationCodes : List LocationCode
    , waveCodes : List WaveCode
    , bases : NonEmpty BaseAudienceData
    , metadata : XBProjectMetadata
    }


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
type alias XBProject =
    { data : WebData XBProjectData
    , id : XBProjectId
    , folderId : Maybe XBFolderId
    , shared : Shared
    , sharingNote : String
    , copiedFrom : Maybe XBProjectId
    , name : String
    , updatedAt : Posix
    , createdAt : Posix
    }


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
type alias XBProjectFullyLoaded =
    { data : XBProjectData
    , id : XBProjectId
    , folderId : Maybe XBFolderId
    , shared : Shared
    , sharingNote : String
    , copiedFrom : Maybe XBProjectId
    , name : String
    , updatedAt : Posix
    , createdAt : Posix
    }


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
projectIcon : Shared -> IconData
projectIcon shared =
    case shared of
        MyPrivateCrosstab ->
            P2Icons.crosstab

        SharedBy _ _ ->
            P2Icons.shared

        MySharedCrosstab _ ->
            P2Icons.sharing

        SharedByLink ->
            P2Icons.shared


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
projectOwner : Shared -> ProjectOwner
projectOwner shared =
    case shared of
        MyPrivateCrosstab ->
            Me

        SharedBy { email } _ ->
            NotMe { email = Maybe.withDefault "unkwown_email" email }

        MySharedCrosstab _ ->
            Me

        SharedByLink ->
            NotMe { email = "unkwown_email" }


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
isSharedWithMe : Shared -> Bool
isSharedWithMe shared =
    case shared of
        MyPrivateCrosstab ->
            False

        SharedBy _ _ ->
            True

        MySharedCrosstab _ ->
            False

        SharedByLink ->
            True


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
isSharedByMeWithOrg : Shared -> Bool
isSharedByMeWithOrg shared =
    case shared of
        MyPrivateCrosstab ->
            False

        SharedBy _ _ ->
            False

        MySharedCrosstab sharees ->
            NonemptyList.any isOrgSharee sharees

        SharedByLink ->
            False


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
isOrgSharee : Sharee -> Bool
isOrgSharee sharee =
    case sharee of
        UserSharee _ ->
            False

        OrgSharee _ ->
            True


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
userShareeEmail : Sharee -> Maybe String
userShareeEmail sharee =
    case sharee of
        UserSharee { email } ->
            Just email

        OrgSharee _ ->
            Nothing


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
isMine : Shared -> Bool
isMine shared =
    case shared of
        MyPrivateCrosstab ->
            True

        SharedBy _ _ ->
            False

        MySharedCrosstab _ ->
            True

        SharedByLink ->
            False


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
isSharedWithMyOrg : Flags -> Shared -> Bool
isSharedWithMyOrg { user } shared =
    let
        sharedWithOrg orgId sharee =
            case sharee of
                UserSharee _ ->
                    False

                OrgSharee id ->
                    id == orgId
    in
    case user.organisationId of
        Just orgId ->
            case shared of
                MyPrivateCrosstab ->
                    False

                SharedBy _ sharees ->
                    NonemptyList.any (sharedWithOrg (XB2.Share.Data.Id.fromString orgId)) sharees

                MySharedCrosstab _ ->
                    False

                SharedByLink ->
                    False

        Nothing ->
            False


{-| TODO: Move this into its own module or related to `CrosstabsProject` type.
-}
fullyLoadedToProject : XBProjectFullyLoaded -> XBProject
fullyLoadedToProject project =
    { id = project.id
    , folderId = project.folderId
    , shared = project.shared
    , sharingNote = project.sharingNote
    , copiedFrom = project.copiedFrom
    , name = project.name
    , updatedAt = project.updatedAt
    , createdAt = project.createdAt
    , data = Success project.data
    }


{-| TODO: Move this into its own module or related to `CrosstabsProject` type.
-}
getFullyLoadedProject : XBProject -> Maybe XBProjectFullyLoaded
getFullyLoadedProject project =
    RemoteData.toMaybe project.data
        |> Maybe.map
            (\data ->
                { id = project.id
                , folderId = project.folderId
                , name = project.name
                , shared = project.shared
                , sharingNote = project.sharingNote
                , copiedFrom = project.copiedFrom
                , updatedAt = project.updatedAt
                , createdAt = project.createdAt
                , data = data
                }
            )


{-| TODO: Move this into its own module or related to `CrosstabsProject` type.
-}
projectHeaderSizeDecoder : Decoder XBProjectHeaderSize
projectHeaderSizeDecoder =
    Decode.succeed XBProjectHeaderSize
        |> Decode.andMap (Decode.field "rowWidth" Decode.int)
        |> Decode.andMap (Decode.field "columnHeight" Decode.int)


{-| TODO: Move this into its own module or related to `CrosstabsProject` type.
-}
frozenCellsDecoder : Decoder ( Int, Int )
frozenCellsDecoder =
    Decode.succeed Tuple.pair
        |> Decode.andMap (Decode.field "rows" Decode.int)
        |> Decode.andMap (Decode.field "columns" Decode.int)


{-| TODO: Move this into its own module or related to `CrosstabsProject` type.
-}
defaultFrozenCells : ( Int, Int )
defaultFrozenCells =
    ( 0, 0 )


defaultMinimumSampleSize : Optional.Optional Int
defaultMinimumSampleSize =
    Optional.Undefined


{-| The default width and height of the top-left header (the one with the
_+ Add an attribute / audience_ button).

Based on this [Figma](https://www.figma.com/file/76WmgwC5AKHHNssl6KpPUA/Crosstab-UI-screens?type=design&node-id=280-110108&mode=design&t=S4ummH40l39MMqhv-4) design.

-}
defaultProjectHeaderSize : XBProjectHeaderSize
defaultProjectHeaderSize =
    { rowWidth = 263, columnHeight = 149 }


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
metadataDecoder : Decoder XBProjectMetadata
metadataDecoder =
    Decode.succeed XBProjectMetadata
        |> Decode.andMap (Decode.field "activeMetrics" <| Decode.list Metric.decoder)
        |> Decode.andMap
            (Decode.optionalField "averageTimeFormat" Average.averageTimeFormatDecoder
                |> Decode.map (Maybe.withDefault Average.HHmm)
            )
        |> Decode.andMap (Decode.field "metricsTransposition" MetricsTransposition.decoder)
        |> Decode.andMap
            (Decode.optionalField "sort" (Decode.field "data" Sort.decoder)
                |> Decode.map (Maybe.withDefault Sort.empty)
            )
        |> Decode.andMap
            (Decode.optionalField "headerSize" projectHeaderSizeDecoder
                |> Decode.map (Maybe.withDefault defaultProjectHeaderSize)
            )
        |> Decode.andMap
            (Decode.optionalField "frozenCells" frozenCellsDecoder
                |> Decode.map (Maybe.withDefault defaultFrozenCells)
            )
        |> Decode.andMap (Optional.decodeField "minimumSampleSize" Decode.int)


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
encodeMetadata : XBProjectMetadata -> Value
encodeMetadata metadata =
    [ ( "activeMetrics", Encode.list Metric.encode metadata.activeMetrics )
    , ( "averageTimeFormat", Average.encodeAverageTimeFormat metadata.averageTimeFormat )
    , ( "metricsTransposition", MetricsTransposition.encode metadata.metricsTransposition )
    , ( "sort"
      , Encode.object
            [ ( "version", Encode.int 1 )
            , ( "data", Sort.encode metadata.sort )
            ]
      )
    , ( "frozenCells"
      , Encode.object
            [ ( "rows", Encode.int (Tuple.first metadata.frozenRowsAndColumns) )
            , ( "columns", Encode.int (Tuple.second metadata.frozenRowsAndColumns) )
            ]
      )
    ]
        |> Optional.addFieldsToKeyValuePairs
            [ ( "minimumSampleSize"
              , Optional.map Encode.int metadata.minimumSampleSize
              )
            ]
        |> List.addIf (metadata.headerSize /= defaultProjectHeaderSize)
            ( "headerSize"
            , Encode.object
                [ ( "rowWidth", Encode.int metadata.headerSize.rowWidth )
                , ( "columnHeight", Encode.int metadata.headerSize.columnHeight )
                ]
            )
        |> Encode.object


defaultMetrics : List Metric
defaultMetrics =
    Metric.allMetrics


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
defaultMetadata : XBProjectMetadata
defaultMetadata =
    { activeMetrics = defaultMetrics
    , averageTimeFormat = Average.HHmm
    , metricsTransposition = MetricsInRows
    , sort = Sort.empty
    , headerSize = defaultProjectHeaderSize
    , frozenRowsAndColumns = defaultFrozenCells
    , minimumSampleSize = defaultMinimumSampleSize
    }


{-| TODO: Move this into its own module or related to `Sharing` type.

TODO: Cognitive complexity of this function is too high, refactor it.

-}
sharedDecoder : String -> Decoder Shared
sharedDecoder myUserId =
    let
        shareeListDecoder : Decoder (Maybe (NonEmpty Sharee))
        shareeListDecoder =
            Decode.field "shared"
                (Decode.list shareeDecoder
                    |> Decode.map (Maybe.values >> NonemptyList.fromList)
                )

        shareeDecoder : Decoder (Maybe Sharee)
        shareeDecoder =
            Decode.oneOf
                [ Decode.succeed CrosstabUser
                    |> Decode.andMap (Decode.field "user_id" intToString)
                    |> Decode.andMap (Decode.field "email" Decode.string)
                    |> Decode.map UserSharee
                    |> Decode.map Just
                , Decode.succeed OrgSharee
                    |> Decode.andMap (Decode.field "org_id" XB2.Share.Data.Id.decodeFromInt)
                    |> Decode.map Just
                , Decode.at [ "error", "error_type" ] Decode.string
                    |> Decode.andThen
                        (\errorType ->
                            case errorType of
                                "sharing_user_not_found" ->
                                    Decode.succeed Nothing

                                "sharing_not_allowed" ->
                                    Decode.succeed Nothing

                                _ ->
                                    Decode.fail <| "Unknown shared error_type: '" ++ errorType ++ "'"
                        )
                ]
    in
    Decode.oneOf
        [ Decode.at [ "shared_by", "user_id" ] intToString
            |> Decode.andThen
                (\sharerUserId ->
                    if myUserId == sharerUserId then
                        shareeListDecoder
                            |> Decode.map
                                (Maybe.unwrap
                                    MyPrivateCrosstab
                                    MySharedCrosstab
                                )

                    else
                        shareeListDecoder
                            |> Decode.andThen
                                (\maybeSharees ->
                                    case maybeSharees of
                                        Nothing ->
                                            Decode.fail "Weird: the list of sharees is empty (some might have been filtered out due to errors, users being deleted, ...) and the crosstab is not ours, so why do we see it?"

                                        Just sharees ->
                                            Decode.oneOf
                                                [ Decode.at [ "shared_by", "email" ] Decode.string
                                                    |> Decode.map (\email -> SharedBy { id = sharerUserId, email = Just email } sharees)
                                                , Decode.at [ "shared_by", "error", "error_type" ] Decode.string
                                                    |> Decode.andThen
                                                        (\errorType ->
                                                            case errorType of
                                                                "sharing_user_not_found" ->
                                                                    Decode.succeed <| SharedBy { id = sharerUserId, email = Nothing } sharees

                                                                "sharing_not_allowed" ->
                                                                    Decode.succeed <| SharedBy { id = sharerUserId, email = Nothing } sharees

                                                                _ ->
                                                                    Decode.fail <| "Unknown shared_by error_type: '" ++ errorType ++ "'"
                                                        )
                                                ]
                                )
                )
        , Decode.optionalField "sharing_type" Decode.string
            |> Decode.andThen
                (\sharingBylink ->
                    if Just sharingByLinkApiIdentifier == sharingBylink then
                        Decode.succeed SharedByLink

                    else
                        Decode.field "shared_by" Decode.emptyObject
                            |> Decode.map (always MyPrivateCrosstab)
                )
        ]


encodeUserForSharing : CrosstabUser -> Value
encodeUserForSharing { email, id } =
    Encode.object
        [ ( "email", Encode.string email )
        , ( "user_id", Encode.encodeStringAsInt id )
        ]


{-| TODO: Move this into its own module or related to `Sharing` type.
-}
encodeShared : Shared -> Value
encodeShared shared =
    let
        notSharing : Value
        notSharing =
            Encode.list identity []
    in
    case shared of
        MyPrivateCrosstab ->
            notSharing

        SharedBy _ _ ->
            notSharing

        MySharedCrosstab sharees ->
            NonemptyList.encodeList
                (\sharee ->
                    case sharee of
                        UserSharee user ->
                            encodeUserForSharing user

                        OrgSharee orgId ->
                            Encode.object [ ( "org_id", XB2.Share.Data.Id.unsafeEncodeAsInt orgId ) ]
                )
                sharees

        SharedByLink ->
            notSharing


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
xbProjectListDecoder : Flags -> Decoder XBProject
xbProjectListDecoder flags =
    let
        copiedFromDecoder =
            Decode.field "copied_from" <| Decode.emptyStringAsNullWith XB2.Share.Data.Id.fromString

        folderIdDecoder =
            Decode.field "folder_id" <| Decode.emptyStringAsNullWith XB2.Share.Data.Id.fromString
    in
    Decode.succeed (XBProject NotAsked)
        |> Decode.andMap (Decode.field "uuid" XB2.Share.Data.Id.decode)
        |> Decode.andMap folderIdDecoder
        |> Decode.andMap (sharedDecoder flags.user.id)
        |> Decode.andMap (Decode.field "sharing_note" Decode.string)
        |> Decode.andMap copiedFromDecoder
        |> Decode.andMap (Decode.field "name" Decode.string)
        |> Decode.andMap (Decode.field "updated_at" Decode.unixIso8601Decoder)
        |> Decode.andMap (Decode.field "created_at" Decode.unixIso8601Decoder)


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
xbProjectFullyLoadedDecoder : Flags -> Decoder XBProjectFullyLoaded
xbProjectFullyLoadedDecoder flags =
    Decode.succeed
        (\{ id, folderId, name, updatedAt, createdAt, shared, sharingNote, copiedFrom } rows columns locationCodes waveCodes bases ownerId metadata ->
            { id = id
            , folderId = folderId
            , shared = shared
            , sharingNote = sharingNote
            , copiedFrom = copiedFrom
            , name = name
            , updatedAt = updatedAt
            , createdAt = createdAt
            , data =
                { rows = rows
                , ownerId = ownerId
                , columns = columns
                , locationCodes = locationCodes
                , waveCodes = waveCodes
                , bases = bases
                , metadata = metadata
                }
            }
        )
        |> Decode.andMap (xbProjectListDecoder flags)
        |> Decode.andMap (Decode.field "rows" <| Decode.list audienceDataDecoder)
        |> Decode.andMap (Decode.field "columns" <| Decode.list audienceDataDecoder)
        |> Decode.andMap (Decode.field "country_codes" <| Decode.list XB2.Share.Data.Id.decode)
        |> Decode.andMap (Decode.field "wave_codes" <| Decode.list XB2.Share.Data.Id.decode)
        |> Decode.andMap (Decode.field "bases" (NonemptyList.decodeList baseAudienceDataDecoder))
        |> Decode.andMap (Decode.field "user_id" intToString)
        |> Decode.andMap
            (Decode.oneOf
                [ Decode.field "metadata" metadataDecoder
                , Decode.succeed defaultMetadata
                ]
            )


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
xbProjectDecoder : Flags -> Decoder XBProject
xbProjectDecoder flags =
    xbProjectFullyLoadedDecoder flags
        |> Decode.map fullyLoadedToProject


{-| TODO: Move this into its own module or related to `CrosstabProject` type.
-}
xbProjectEncode : XBProject -> Value
xbProjectEncode project =
    let
        dataFields =
            project.data
                |> RemoteData.map
                    (\data ->
                        [ ( "rows", Encode.list audienceDataEncode data.rows )
                        , ( "columns", Encode.list audienceDataEncode data.columns )
                        , ( "country_codes", Encode.list XB2.Share.Data.Id.encode data.locationCodes )
                        , ( "wave_codes", Encode.list XB2.Share.Data.Id.encode data.waveCodes )
                        , ( "bases", NonemptyList.encodeList baseAudienceDataEncode data.bases )
                        , ( "metadata", encodeMetadata data.metadata )
                        , ( "copied_from", Maybe.unwrap Encode.null XB2.Share.Data.Id.encode project.copiedFrom )
                        , ( "shared", encodeShared project.shared )
                        , ( "sharing_note", Encode.string project.sharingNote )
                        , ( "folder_id", Maybe.unwrap Encode.null XB2.Share.Data.Id.encode project.folderId )
                        ]
                    )
                |> RemoteData.withDefault []
    in
    Encode.object <|
        ( "name", Encode.string project.name )
            :: dataFields


doNotShowAgainDecoder : Decoder (Maybe DoNotShowAgain)
doNotShowAgainDecoder =
    let
        decode str =
            case str of
                "DeleteRowsColumnsModal" ->
                    Decode.succeed <| Just DeleteRowsColumnsModal

                "DeleteBasesModal" ->
                    Decode.succeed <| Just DeleteBasesModal

                _ ->
                    -- We don't care anymore about unknown userSettings (QA)
                    Decode.succeed Nothing
    in
    Decode.andThen decode Decode.string


doNotShowAgainEncode : DoNotShowAgain -> Value
doNotShowAgainEncode doNotShowAgain =
    Encode.string <|
        case doNotShowAgain of
            DeleteRowsColumnsModal ->
                "DeleteRowsColumnsModal"

            DeleteBasesModal ->
                "DeleteBasesModal"


canShow : DoNotShowAgain -> XBUserSettings -> Bool
canShow doNotShowAgain settings =
    not <| List.member doNotShowAgain settings.doNotShowAgain


{-| TODO: Move this into its own module or related to `Settings` type.

TODO: This decoding depends on order and is bug-prone.

-}
xbUserSettingsDecoder : Decoder XBUserSettings
xbUserSettingsDecoder =
    Decode.field "data"
        (Decode.succeed XBUserSettings
            |> Decode.andMap
                (Decode.optionalField "can_show_shared_project_warning" Decode.bool
                    {- If the field is missing, that means user hasn't interacted
                       with this checkbox yet, and thus we need to show the warning
                       to them. So, absence of the field -> True
                    -}
                    |> Decode.map (Maybe.withDefault True)
                )
            |> Decode.andMap
                (Decode.optionalField "xb2_list_ftue_seen" Decode.bool
                    |> Decode.map (Maybe.withDefault False)
                )
            |> Decode.andMap
                (Decode.optionalField "do_not_show_again" (Decode.list doNotShowAgainDecoder)
                    |> Decode.map (Maybe.andThen Maybe.combine >> Maybe.withDefault [])
                )
            |> Decode.andMap
                (Decode.optionalField "renaming_cells_onboarding_seen" Decode.bool
                    |> Decode.map (Maybe.withDefault False)
                )
            |> Decode.andMap
                (Decode.optionalField "freeze_rows_columns_onboarding_seen" Decode.bool
                    |> Decode.map (Maybe.withDefault False)
                )
            |> Decode.andMap
                (Decode.optionalField "unfreeze_the_filters" Decode.bool
                    |> Decode.map (Maybe.withDefault False)
                )
            |> Decode.andMap
                (Decode.optionalField "show_detail_table_in_debug_mode" Decode.bool
                    |> Decode.map (Maybe.withDefault False)
                )
            |> Decode.andMap
                (Decode.optionalField "pin_debug_options" Decode.bool
                    |> Decode.map (Maybe.withDefault False)
                )
            |> Decode.andMap
                (Decode.optionalField "edit_ab_onboarding_seen" Decode.bool
                    |> Decode.map (Maybe.withDefault False)
                )
        )


{-| TODO: Move this into its own module or related to `Settings` type.
-}
xbUserSettingsEncode : XBUserSettings -> Value
xbUserSettingsEncode settings =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "can_show_shared_project_warning"
                  , Encode.bool settings.canShowSharedProjectWarning
                  )
                , ( "xb2_list_ftue_seen", Encode.bool settings.xb2ListFTUESeen )
                , ( "do_not_show_again"
                  , Encode.list doNotShowAgainEncode settings.doNotShowAgain
                  )
                , ( "renaming_cells_onboarding_seen"
                  , Encode.bool settings.renamingCellsOnboardingSeen
                  )
                , ( "freeze_rows_columns_onboarding_seen"
                  , Encode.bool settings.freezeRowsColumnsOnboardingSeen
                  )
                , ( "unfreeze_the_filters"
                  , Encode.bool settings.unfreezeTheFilters
                  )
                , ( "show_detail_table_in_debug_mode"
                  , Encode.bool settings.showDetailTableInDebugMode
                  )
                , ( "pin_debug_options", Encode.bool settings.pinDebugOptions )
                , ( "edit_ab_onboarding_seen"
                  , Encode.bool settings.editAttributeExpressionOnboardingSeen
                  )
                ]
          )
        ]


{-| TODO: Extract API calls into the proper Api namespace.
-}
createXBProject : XBProject -> Flags -> HttpCmd XBProjectError XBProject
createXBProject project flags =
    Http.request
        { method = "POST"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ namespaceNoLeadingSlash ]
                []
        , body = Http.jsonBody <| xbProjectEncode project
        , expect = XB2.Share.Gwi.Http.expectErrorAwareJson xbProjectErrorDecoder (xbProjectDecoder flags)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
fetchXBProjectList : Flags -> HttpCmd XBProjectError (List XBProject)
fetchXBProjectList flags =
    Http.request
        { method = "GET"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2", "saved", "crosstabs" ]
                []
        , body = Http.emptyBody
        , expect =
            XB2.Share.Gwi.Http.expectErrorAwareJson xbProjectErrorDecoder
                (Decode.field "projects" (Decode.list (xbProjectListDecoder flags)))
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
fetchXBProject : XBProjectId -> Flags -> HttpCmd XBProjectError XBProject
fetchXBProject projectId flags =
    Http.request
        { method = "GET"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2", "saved", "crosstabs", XB2.Share.Data.Id.unwrap projectId ]
                []
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectErrorAwareJson xbProjectErrorDecoder (xbProjectDecoder flags)
        , timeout = Nothing
        , tracker = Nothing
        }


fetchTaskXBProjectFullyLoaded : XBProject -> Flags -> Task (XB2.Share.Gwi.Http.Error XBProjectError) XBProjectFullyLoaded
fetchTaskXBProjectFullyLoaded p flags =
    Http.task
        { method = "GET"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2", "saved", "crosstabs", XB2.Share.Data.Id.unwrap p.id ]
                []
        , body = Http.emptyBody
        , resolver = XB2.Share.Gwi.Http.resolveErrorAwareJson xbProjectErrorDecoder (xbProjectFullyLoadedDecoder flags)
        , timeout = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
fetchXBUserSettings : Flags -> HttpCmd Never XBUserSettings
fetchXBUserSettings flags =
    Http.request
        { method = "GET"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2", "crosstabs", "saved", "user_settings" ]
                []
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectJson identity xbUserSettingsDecoder
        , tracker = Nothing
        , timeout = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
updateXBUserSettings : XBUserSettings -> Flags -> HttpCmd Never XBUserSettings
updateXBUserSettings settings flags =
    Http.request
        { method = "POST"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2", "crosstabs", "saved", "user_settings" ]
                []
        , body = Http.jsonBody <| xbUserSettingsEncode settings
        , expect = XB2.Share.Gwi.Http.expectJson identity xbUserSettingsDecoder
        , tracker = Nothing
        , timeout = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
patchXBProject : XBProject -> Flags -> HttpCmd XBProjectError XBProject
patchXBProject project flags =
    Http.request
        { method = "PATCH"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ namespaceNoLeadingSlash, XB2.Share.Data.Id.unwrap project.id ]
                []
        , body =
            Http.jsonBody <|
                Encode.object
                    [ ( "name", Encode.string project.name )
                    , ( "shared", encodeShared project.shared )
                    , ( "sharing_note", Encode.string project.sharingNote )
                    , ( "folder_id", Maybe.unwrap (Encode.string "") XB2.Share.Data.Id.encode project.folderId )
                    ]
        , expect = XB2.Share.Gwi.Http.expectErrorAwareJson xbProjectErrorDecoder (xbProjectDecoder flags)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
shareXBProjectWithLink : XBProject -> Flags -> HttpCmd XBProjectError XBProject
shareXBProjectWithLink project flags =
    Http.request
        { method = "POST"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2/saved/crosstabs/share", XB2.Share.Data.Id.unwrap project.id ]
                []
        , body =
            Http.jsonBody <|
                Encode.list identity
                    [ Encode.object
                        [ ( "type", Encode.string sharingByLinkApiIdentifier )
                        ]
                    ]
        , expect = XB2.Share.Gwi.Http.expectErrorAwareJson xbProjectErrorDecoder (Decode.succeed project)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
patchXBProjectTask : XBProject -> Flags -> Task (XB2.Share.Gwi.Http.Error XBProjectError) XBProject
patchXBProjectTask project flags =
    Http.task
        { method = "PATCH"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ namespaceNoLeadingSlash, XB2.Share.Data.Id.unwrap project.id ]
                []
        , body =
            Http.jsonBody <|
                Encode.object
                    [ ( "name", Encode.string project.name )
                    , ( "shared", encodeShared project.shared )
                    , ( "sharing_note", Encode.string project.sharingNote )
                    , ( "folder_id", Maybe.unwrap (Encode.string "") XB2.Share.Data.Id.encode project.folderId )
                    ]
        , resolver = XB2.Share.Gwi.Http.resolveErrorAwareJson xbProjectErrorDecoder (xbProjectDecoder flags)
        , timeout = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
destroyXBProjectTask : XBProject -> Flags -> Task (XB2.Share.Gwi.Http.Error XBProjectError) XBProject
destroyXBProjectTask project flags =
    Http.task
        { method = "DELETE"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ namespaceNoLeadingSlash, XB2.Share.Data.Id.unwrap project.id ]
                []
        , body = Http.emptyBody
        , resolver = XB2.Share.Gwi.Http.resolveErrorAwareJson xbProjectErrorDecoder (Decode.succeed project)
        , timeout = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
updateXBProject : XBProject -> Flags -> HttpCmd XBProjectError XBProject
updateXBProject project flags =
    Http.request
        { method = "PUT"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ namespaceNoLeadingSlash, XB2.Share.Data.Id.unwrap project.id ]
                []
        , body = Http.jsonBody <| xbProjectEncode project
        , expect = XB2.Share.Gwi.Http.expectErrorAwareJson xbProjectErrorDecoder (xbProjectDecoder flags)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
destroyXBProject : XBProject -> Flags -> HttpCmd XBProjectError ()
destroyXBProject project flags =
    Http.request
        { method = "DELETE"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ namespaceNoLeadingSlash, XB2.Share.Data.Id.unwrap project.id ]
                []
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectErrorAwareJson xbProjectErrorDecoder (Decode.succeed ())
        , timeout = Nothing
        , tracker = Nothing
        }


type SharingEmail
    = UncheckedEmail { email : String }
    | ValidEmail CrosstabUser
    | InvalidEmail { email : String }


type SharedError
    = UserNotFound
    | UserNotProfessional
    | OtherError Int String


sharedErrorDecoder : Decoder SharedError
sharedErrorDecoder =
    let
        decodeError errType err code =
            case errType of
                "sharing_user_not_found" ->
                    UserNotFound

                "sharing_not_allowed" ->
                    UserNotProfessional

                "internal_server_error" ->
                    OtherError code err

                _ ->
                    OtherError code err
    in
    Decode.succeed decodeError
        |> Decode.andMap (Decode.field "error_type" Decode.string)
        |> Decode.andMap (Decode.field "error" Decode.string)
        |> Decode.andMap (Decode.field "code" Decode.int)


unwrapSharingEmail : SharingEmail -> String
unwrapSharingEmail sharingEmail =
    case sharingEmail of
        UncheckedEmail { email } ->
            email

        ValidEmail { email } ->
            email

        InvalidEmail { email } ->
            email


isUncheckedSharingEmail : SharingEmail -> Bool
isUncheckedSharingEmail sharingEmail =
    case sharingEmail of
        UncheckedEmail _ ->
            True

        ValidEmail _ ->
            False

        InvalidEmail _ ->
            False


getValidFullUserEmail : SharingEmail -> Maybe FullUserEmail
getValidFullUserEmail =
    getValidEmailCrosstabUser
        >> Maybe.map
            (\{ id, email } ->
                { id = XB2.Share.Data.Id.fromString id
                , email = email
                , firstName = ""
                , lastName = ""
                }
            )


getValidEmailCrosstabUser : SharingEmail -> Maybe CrosstabUser
getValidEmailCrosstabUser sharingEmail =
    case sharingEmail of
        UncheckedEmail _ ->
            Nothing

        ValidEmail user ->
            Just user

        InvalidEmail _ ->
            Nothing


fullUserEmailToValidSharingEmail : FullUserEmail -> SharingEmail
fullUserEmailToValidSharingEmail { id, email } =
    ValidEmail { id = XB2.Share.Data.Id.unwrap id, email = email }


sharingEmailDecoder : String -> Decoder SharingEmail
sharingEmailDecoder inputEmail =
    let
        decodeEmailId =
            Decode.map3
                (\id email maybeError ->
                    case maybeError of
                        Just _ ->
                            -- TODO use different error types for some UI messages?
                            InvalidEmail { email = email }

                        Nothing ->
                            ValidEmail { email = email, id = id }
                )
                (Decode.field "user_id" intToString)
                (Decode.field "email" Decode.string)
                (Decode.optionalField "error" sharedErrorDecoder)
    in
    Decode.list decodeEmailId
        |> Decode.map
            (\list ->
                list
                    |> List.head
                    |> Maybe.withDefault (InvalidEmail { email = inputEmail })
            )


encodeSharingEmail : SharingEmail -> Value
encodeSharingEmail =
    NonemptyList.singleton >> encodeSharingEmails


encodeSharingEmails : NonEmpty SharingEmail -> Value
encodeSharingEmails emails =
    let
        encodeEmail : SharingEmail -> Maybe (List ( String, Value ))
        encodeEmail sharingEmail =
            case sharingEmail of
                ValidEmail { email, id } ->
                    Just
                        [ ( "email", Encode.string email )
                        , ( "user_id", Encode.encodeStringAsInt id )
                        ]

                UncheckedEmail { email } ->
                    Just [ ( "email", Encode.string email ) ]

                InvalidEmail _ ->
                    Nothing
    in
    emails
        |> NonemptyList.toList
        |> List.filterMap encodeEmail
        |> Encode.list Encode.object


{-| TODO: Extract API calls into the proper Api namespace.
-}
validateUserEmail : String -> Flags -> HttpCmd SharedError SharingEmail
validateUserEmail email flags =
    let
        customErrorDecoder =
            Decode.index 0 <| Decode.field "error" sharedErrorDecoder
    in
    Http.request
        { method = "POST"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin
                (host flags)
                [ "v2/crosstabs/saved", "share", "validate" ]
                []
        , body =
            Http.jsonBody <|
                Encode.object
                    [ ( "shared"
                      , encodeSharingEmail (UncheckedEmail { email = email })
                      )
                    ]
        , expect =
            XB2.Share.Gwi.Http.expectErrorAwareJson
                customErrorDecoder
                (sharingEmailDecoder email)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
validateUserEmailWithoutErrorDecoding : String -> Flags -> HttpCmd Never SharingEmail
validateUserEmailWithoutErrorDecoding email flags =
    Http.request
        { method = "POST"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin
                (host flags)
                [ "v2/crosstabs/saved", "share", "validate" ]
                []
        , body =
            Http.jsonBody <|
                Encode.object
                    [ ( "shared"
                      , encodeSharingEmail (UncheckedEmail { email = email })
                      )
                    ]
        , expect =
            XB2.Share.Gwi.Http.expectJson
                identity
                (sharingEmailDecoder email)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
unshareMe : XBProject -> Flags -> HttpCmd Never ()
unshareMe project flags =
    Http.request
        { method = "DELETE"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2/crosstabs/saved", "share", "remove", XB2.Share.Data.Id.unwrap project.id ]
                []
        , body = Http.emptyBody
        , expect = Http.expectStringResponse identity (\_ -> Ok ())
        , timeout = Nothing
        , tracker = Nothing
        }


unshareMeTask : XBProject -> Flags -> Task (XB2.Share.Gwi.Http.Error XBProjectError) XBProject
unshareMeTask project flags =
    Http.task
        { method = "DELETE"
        , headers = [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2/crosstabs/saved", "share", "remove", XB2.Share.Data.Id.unwrap project.id ]
                []
        , body = Http.emptyBody
        , resolver = XB2.Share.Gwi.Http.resolveErrorAwareJson xbProjectErrorDecoder (Decode.succeed project)
        , timeout = Nothing
        }


xbProjectErrorToHttpError : XBProjectError -> Http.Error
xbProjectErrorToHttpError err =
    let
        badRequest =
            400

        forbidden =
            403
    in
    Http.BadStatus <|
        case err of
            InvalidUUID ->
                404

            DifferentOwner ->
                forbidden

            OwnershipChangeNotAllowed ->
                forbidden

            UniqueConstraint ->
                badRequest

            BadShareeNotProfessional _ ->
                badRequest

            BadSharee _ ->
                badRequest


xbProjectErrorDisplay : XBProjectError -> ErrorDisplay Never
xbProjectErrorDisplay err =
    case err of
        InvalidUUID ->
            { title = "Invalid project UUID"
            , body = Html.text "The project UUID (eg. from a link you opened) is invalid."
            , details = []
            , errorId = Nothing
            }

        DifferentOwner ->
            { title = "Shared Project Permissions"
            , body = Html.text "Please save as a new project before trying again."
            , details = []
            , errorId = Nothing
            }

        OwnershipChangeNotAllowed ->
            { title = "Ownership change not allowed"
            , body = Html.text "Ownership change not allowed."
            , details = []
            , errorId = Nothing
            }

        UniqueConstraint ->
            { title = "Project name conflict"
            , body = Html.text "A saved crosstab with that name already exists within your organisation. Please use another name."
            , details = []
            , errorId = Nothing
            }

        BadShareeNotProfessional { id, email } ->
            { title = "Sharee no longer has access to Crosstabs"
            , body =
                Html.div []
                    [ Html.div [] [ Html.text "The sharee below cannot be shared with anymore; you'll need to remove them from your list of sharees before continuing." ]
                    , Html.ul []
                        [ Html.li []
                            [ Html.text "User ID: "
                            , Html.strong [] [ Html.text id ]
                            ]
                        , Html.li []
                            [ Html.text "User email: "
                            , Html.strong [] [ Html.text email ]
                            ]
                        ]
                    ]
            , details = []
            , errorId = Nothing
            }

        BadSharee badSharee ->
            { title = "Sharee error"
            , body =
                Html.div []
                    [ Html.div [] [ Html.text "There has been an error sharing with the sharee below:" ]
                    , Html.ul []
                        [ Html.li []
                            [ Html.text "User ID: "
                            , Html.strong [] [ Html.text badSharee.id ]
                            ]
                        , Html.li []
                            [ Html.text "User email: "
                            , Html.strong [] [ Html.text badSharee.email ]
                            ]
                        , Html.li []
                            [ Html.text "Error message: "
                            , Html.strong [] [ Html.text badSharee.errorMessage ]
                            ]
                        , Html.li []
                            [ Html.text "Error type: "
                            , Html.strong [] [ Html.text badSharee.errorType ]
                            ]
                        ]
                    ]
            , details = []
            , errorId = Nothing
            }


xbProjectErrorDecoder : Decoder XBProjectError
xbProjectErrorDecoder =
    Decode.oneOf
        [ CoreError.typeDecoder
            |> Decode.andThen
                (\errorType ->
                    case errorType of
                        "invalid_uuid" ->
                            Decode.succeed InvalidUUID

                        "different_owner" ->
                            Decode.succeed DifferentOwner

                        "ownership_change_not_allowed" ->
                            Decode.succeed OwnershipChangeNotAllowed

                        "unique_constraint" ->
                            Decode.succeed UniqueConstraint

                        _ ->
                            Decode.fail <| "Failed to determine XBProjectError from error_type: " ++ errorType
                )
        , -- ATC-3833: an error hidden deep inside `shared` field of the XB project
          Decode.field "shared" (Decode.list (Decode.maybe badShareeDecoder))
            |> Decode.map (Maybe.values >> List.head)
            |> Decode.andThen
                (\maybeError ->
                    case maybeError of
                        Nothing ->
                            Decode.fail "Didn't find anything bad in the `shared` XB project field"

                        Just error ->
                            Decode.succeed error
                )
        ]


badShareeDecoder : Decoder XBProjectError
badShareeDecoder =
    Decode.map4
        (\id email msg type_ ->
            case ( msg, type_ ) of
                ( "user's plan is not allowed to use sharing", "sharing_not_allowed" ) ->
                    BadShareeNotProfessional { id = id, email = email }

                _ ->
                    BadSharee
                        { id = id
                        , email = email
                        , errorMessage = msg
                        , errorType = type_
                        }
        )
        (Decode.field "user_id" Decode.intToString)
        (Decode.field "email" Decode.string)
        (Decode.at [ "error", "error" ] Decode.string)
        (Decode.at [ "error", "error_type" ] Decode.string)



-- XBFolder


type XBFolderIdTag
    = XBFolderIdTag


type alias XBFolderId =
    Id XBFolderIdTag


type alias XBFolder =
    { id : XBFolderId
    , name : String
    }


xbFolderDecoder : Decoder XBFolder
xbFolderDecoder =
    Decode.succeed XBFolder
        |> Decode.andMap (Decode.field "id" XB2.Share.Data.Id.decode)
        |> Decode.andMap (Decode.field "name" Decode.string)


{-| TODO: Extract API calls into the proper Api namespace.
-}
fetchXBFolders : Flags -> HttpCmd Never (List XBFolder)
fetchXBFolders flags =
    Http.request
        { method = "GET"
        , url = Url.Builder.crossOrigin (host flags) [ "v2/crosstabs/saved", "folders" ] []
        , headers = [ Auth.header flags.token ]
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectJson identity <| Decode.field "data" (Decode.list xbFolderDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
createXBFolder : XBFolder -> Flags -> HttpCmd Never XBFolder
createXBFolder folder flags =
    Http.request
        { method = "POST"
        , headers = [ Auth.header flags.token ]
        , url = Url.Builder.crossOrigin (host flags) [ "v2/crosstabs/saved", "folders" ] []
        , body = Http.jsonBody <| Encode.object [ ( "name", Encode.string folder.name ) ]
        , expect = XB2.Share.Gwi.Http.expectJson identity xbFolderDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
renameXBFolder : XBFolder -> Flags -> HttpCmd Never XBFolder
renameXBFolder folder flags =
    Http.request
        { method = "PATCH"
        , headers = [ Auth.header flags.token ]
        , url = Url.Builder.crossOrigin (host flags) [ "v2/crosstabs/saved", "folders", XB2.Share.Data.Id.unwrap folder.id ] []
        , body = Http.jsonBody <| Encode.object [ ( "name", Encode.string folder.name ) ]
        , expect = XB2.Share.Gwi.Http.expectJson identity xbFolderDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
destroyXBFolderWithContent : XBFolder -> Flags -> HttpCmd Never ()
destroyXBFolderWithContent folder flags =
    Http.request
        { method = "DELETE"
        , headers = [ Auth.header flags.token ]
        , url = Url.Builder.crossOrigin (host flags) [ "v2/crosstabs/saved", "folders", XB2.Share.Data.Id.unwrap folder.id, "recursive" ] []
        , body = Http.emptyBody
        , expect = Http.expectStringResponse identity (\_ -> Ok ())
        , timeout = Nothing
        , tracker = Nothing
        }


{-| TODO: Extract API calls into the proper Api namespace.
-}
destroyXBFolder : XBFolder -> Flags -> HttpCmd Never ()
destroyXBFolder folder flags =
    Http.request
        { method = "DELETE"
        , headers = [ Auth.header flags.token ]
        , url = Url.Builder.crossOrigin (host flags) [ "v2/crosstabs/saved", "folders", XB2.Share.Data.Id.unwrap folder.id ] []
        , body = Http.emptyBody
        , expect = Http.expectStringResponse identity (\_ -> Ok ())
        , timeout = Nothing
        , tracker = Nothing
        }


projectDataNamespaceCodes : XBProjectData -> List Namespace.Code
projectDataNamespaceCodes data =
    (data.rows ++ data.columns)
        |> List.fastConcatMap (.definition >> definitionNamespaceCodes)
        |> Set.Any.fromList Namespace.codeToString
        |> Set.Any.toList


definitionNamespaceCodes : AudienceDefinition -> List Namespace.Code
definitionNamespaceCodes definition =
    case definition of
        Average avg ->
            [ avg
                |> Average.getQuestionCode
                |> XB2.Share.Data.Labels.questionCodeToNamespaceCode
            ]

        Expression expr ->
            expr
                |> Expression.getNamespaceCodes


definitionNamespaceAndQuestionCodes : AudienceDefinition -> List NamespaceAndQuestionCode
definitionNamespaceAndQuestionCodes definition =
    case definition of
        Average avg ->
            [ Average.getQuestionCode avg ]

        Expression expr ->
            expr
                |> Expression.getQuestionCodes
                |> Set.Any.fromList XB2.Share.Data.Id.unwrap
                |> Set.Any.toList


getProjectQuestionCodes : XBProjectFullyLoaded -> List NamespaceAndQuestionCode
getProjectQuestionCodes project =
    (NonemptyList.toList project.data.bases
        |> List.fastConcatMap (.expression >> Expression.getQuestionCodes)
    )
        ++ List.fastConcatMap (.definition >> definitionNamespaceAndQuestionCodes) project.data.rows
        ++ List.fastConcatMap (.definition >> definitionNamespaceAndQuestionCodes) project.data.columns
        |> unique


getCrosstabDatasetCodes : List AudienceDefinition -> List Expression -> Store -> List DatasetCode
getCrosstabDatasetCodes rowsAncCols bases store =
    let
        datasetsToNamespaces : BiDict XB2.Share.Data.Platform2.DatasetCode Namespace.Code
        datasetsToNamespaces =
            store.datasetsToNamespaces
                |> RemoteData.withDefault BiDict.empty

        datasesFromDefinitions : XB2.Share.Data.Id.IdSet DatasetCodeTag
        datasesFromDefinitions =
            rowsAncCols
                |> List.foldr
                    (\definition acc ->
                        let
                            datasetCodes =
                                case definition of
                                    Expression expr ->
                                        XB2.Share.Data.Platform2.datasetsFromExpression datasetsToNamespaces store.lineages expr

                                    Average average ->
                                        Average.getDatasets datasetsToNamespaces store.lineages average
                        in
                        datasetCodes
                            |> RemoteData.withDefault [ XB2.Share.Data.Id.fromString "n/a" ]
                            |> Set.Any.fromList XB2.Share.Data.Id.unwrap
                            |> Set.Any.union acc
                    )
                    XB2.Share.Data.Id.emptySet
    in
    bases
        |> List.foldr
            (\expr acc ->
                XB2.Share.Data.Platform2.datasetsFromExpression datasetsToNamespaces store.lineages expr
                    |> RemoteData.withDefault [ XB2.Share.Data.Id.fromString "n/a" ]
                    |> Set.Any.fromList XB2.Share.Data.Id.unwrap
                    |> Set.Any.union acc
            )
            datasesFromDefinitions
        |> Set.Any.toList


getProjectDatasetNames : List AudienceDefinition -> List Expression -> Store -> List String
getProjectDatasetNames rowsAncCols bases store =
    let
        allDatasets : XB2.Share.Data.Id.IdDict DatasetCodeTag XB2.Share.Data.Platform2.Dataset
        allDatasets =
            RemoteData.withDefault XB2.Share.Data.Id.emptyDict store.datasets
    in
    getCrosstabDatasetCodes rowsAncCols bases store
        |> List.filterMap
            (\code -> Dict.Any.get code allDatasets |> Maybe.map .name)
