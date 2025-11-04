module XB2.Share.Store.Platform2 exposing
    ( AudienceRelatedMsg(..)
    , Config
    , Configure
    , Msg(..)
    , Store
    , StoreAction(..)
    , configure
    , createAudienceWithExpression
    , getAllLocationsIfLoaded
    , getAllWavesIfLoaded
    , getDatapointMaybe
    , getQuestion
    , getQuestionMaybe
    , init
    , storeActionMany
    , update
    )

import BiDict.Assoc as BiDict exposing (BiDict)
import Cmd.Extra as Cmd
import Dict exposing (Dict)
import Dict.Any
import Http
import List.NonEmpty as NonemptyList
import Maybe.Extra as Maybe
import RemoteData exposing (RemoteData(..), WebData)
import XB2.Data.Audience as Audience
import XB2.Data.Audience.Expression exposing (Expression)
import XB2.Data.Audience.Folder as AudienceFolder
import XB2.Data.Dataset as Dataset
import XB2.Data.Namespace as Namespace
import XB2.Share.Config exposing (Flags)
import XB2.Share.Data.Id exposing (IdDict)
import XB2.Share.Data.Labels as Labels
    exposing
        ( Category
        , CategoryIdTag
        , Datapoint
        , Location
        , LocationCodeTag
        , NamespaceAndQuestionCode
        , NamespaceAndQuestionCodeTag
        , NamespaceLineage
        , Question
        , QuestionAndDatapointCode
        , Region
        , Wave
        , WaveCodeTag
        )
import XB2.Share.Data.Platform2
    exposing
        ( ChartFolder
        , ChartFolderIdTag
        , DatasetFolder
        , Splitter
        , SplitterCodeTag
        , Timezone
        , TimezoneCodeTag
        )
import XB2.Share.Gwi.Http exposing (Error, HttpCmd)
import XB2.Share.Gwi.RemoteData as RemoteData
import XB2.Share.Store.Utils as Store


type alias Config msg =
    { msg : Msg -> msg
    , err : (Store -> Store) -> Error Never -> msg
    , errWithoutModal : (Store -> Store) -> Error Never -> msg
    , simpleErr : Error Never -> msg
    , notFoundError : (Store -> Store) -> msg
    }


type alias Configure msg =
    { msg : Msg -> msg
    , err : (Store -> Store) -> Error Never -> msg
    , errWithoutModal : (Store -> Store) -> Error Never -> msg
    , notFoundError : (Store -> Store) -> msg
    }


configure : Configure msg -> Config msg
configure c =
    { msg = c.msg
    , err = c.err
    , errWithoutModal = c.errWithoutModal
    , simpleErr = c.err identity
    , notFoundError = c.notFoundError
    }


type AudienceRelatedMsg
    = AudienceFoldersFetched (List AudienceFolder.Folder)
    | AudienceWithExpressionCreated (WebData (Dict.Any.AnyDict Audience.StringifiedId Audience.Id Audience.Audience)) Audience.Audience


type Msg
    = AudienceRelatedMsg AudienceRelatedMsg
    | QuestionFetched NamespaceAndQuestionCode Question
    | QuestionFetchError NamespaceAndQuestionCode Bool (Store -> Store) (Error Never)
    | LocationsFetched (List Location)
    | LocationsByNamespaceFetched Namespace.Code (List Location)
    | WavesFetched (List Wave)
    | WavesByNamespaceFetched Namespace.Code (List Wave)
    | DatasetFoldersFetched (List DatasetFolder)
    | DatasetsFetched (List Dataset.Dataset)
    | LineageFetched Namespace.Code NamespaceLineage


type StoreAction
    = FetchAudienceFolders
    | FetchAllLocations
    | FetchLocationsByNamespace Namespace.Code
    | FetchAllWaves
    | FetchWavesByNamespace Namespace.Code
    | FetchQuestion { showErrorModal : Bool } NamespaceAndQuestionCode
    | FetchDatasetFolders
    | FetchDatasets
    | FetchLineage Namespace.Code


type alias Store =
    { audienceFolders : WebData (Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder)
    , audiences : WebData (Dict.Any.AnyDict Audience.StringifiedId Audience.Id Audience.Audience)
    , audiencesV1ToV2 : WebData (Dict.Any.AnyDict Audience.StringifiedId Audience.Id Audience.Audience)
    , splitters : Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData (IdDict SplitterCodeTag Splitter))
    , questions : IdDict NamespaceAndQuestionCodeTag (WebData Question)
    , categories : WebData (IdDict CategoryIdTag Category)
    , locations : WebData (IdDict LocationCodeTag Location)
    , locationsByNamespace : Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData (IdDict LocationCodeTag Location))
    , allRegions : WebData (Dict Int Region)
    , regionsByNamespace : Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData (Dict Int Region))
    , waves : WebData (IdDict WaveCodeTag Wave)
    , wavesByNamespace : Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData (IdDict WaveCodeTag Wave))
    , datasetFoldersTree : WebData (List DatasetFolder)
    , datasets : WebData (Dict.Any.AnyDict Dataset.StringifiedCode Dataset.Code Dataset.Dataset)
    , datasetsToNamespaces : WebData (BiDict Dataset.Code Namespace.Code)
    , chartFolders : WebData (IdDict ChartFolderIdTag ChartFolder)
    , lineages : Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    , timezones : WebData (IdDict TimezoneCodeTag Timezone)
    , timezonesOrdered : WebData (List Timezone)
    }


init : Store
init =
    { audienceFolders = NotAsked
    , audiences = NotAsked
    , audiencesV1ToV2 = NotAsked
    , splitters = Dict.Any.empty Namespace.codeToString
    , questions = XB2.Share.Data.Id.emptyDict
    , categories = NotAsked
    , locations = NotAsked
    , locationsByNamespace = Dict.Any.empty Namespace.codeToString
    , allRegions = NotAsked
    , regionsByNamespace = Dict.Any.empty Namespace.codeToString
    , waves = NotAsked
    , wavesByNamespace = Dict.Any.empty Namespace.codeToString
    , datasetFoldersTree = NotAsked
    , datasets = NotAsked
    , datasetsToNamespaces = NotAsked
    , chartFolders = NotAsked
    , lineages = Dict.Any.empty Namespace.codeToString
    , timezones = NotAsked
    , timezonesOrdered = NotAsked
    }



-- Network


type alias FetchConfig a b msg =
    { getState : Store -> WebData a
    , setNonSuccess : WebData a -> Store -> Store
    , onSuccess : b -> Msg
    , onError : Maybe (Bool -> (Store -> Store) -> Error Never -> msg)
    , request : Flags -> HttpCmd Never b
    , showErrorModal : Bool
    }


getLocations : Namespace.Code -> Store -> WebData (IdDict LocationCodeTag Location)
getLocations namespaceCode =
    .locationsByNamespace
        >> Dict.Any.get namespaceCode
        >> Maybe.withDefault NotAsked


getWaves : Namespace.Code -> Store -> WebData (IdDict WaveCodeTag Wave)
getWaves namespaceCode =
    .wavesByNamespace
        >> Dict.Any.get namespaceCode
        >> Maybe.withDefault NotAsked


getAllWavesIfLoaded : List Namespace.Code -> Store -> WebData (IdDict WaveCodeTag Wave)
getAllWavesIfLoaded namespaceCodes store =
    if List.isEmpty namespaceCodes then
        NotAsked

    else
        namespaceCodes
            |> RemoteData.traverse (\namespace -> getWaves namespace store)
            |> RemoteData.map (List.foldl Dict.Any.union XB2.Share.Data.Id.emptyDict)


getAllLocationsIfLoaded : List Namespace.Code -> Store -> WebData (IdDict LocationCodeTag Location)
getAllLocationsIfLoaded namespaceCodes store =
    if List.isEmpty namespaceCodes then
        NotAsked

    else
        namespaceCodes
            |> RemoteData.traverse (\namespace -> getLocations namespace store)
            |> RemoteData.map (List.foldl Dict.Any.union XB2.Share.Data.Id.emptyDict)


fetch_ : FetchConfig a b msg -> Config msg -> Flags -> Store -> ( Store, Cmd msg )
fetch_ r { msg, err, errWithoutModal } flags store =
    let
        errMsg =
            if r.showErrorModal then
                err

            else
                errWithoutModal
    in
    Store.peek
        never
        r.getState
        (msg << r.onSuccess)
        (Maybe.unwrap errMsg (\onError -> \s -> onError r.showErrorModal s) r.onError)
        r.request
        (\store_ result ->
            Maybe.unwrap
                (r.setNonSuccess Loading store_)
                (\e -> r.setNonSuccess (Failure e) store_)
                result
        )
        flags
        store


fetch : StoreAction -> Config msg -> Flags -> Store -> ( Store, Cmd msg )
fetch action =
    let
        fetchWithoutCustomError r =
            fetch_
                { getState = r.getState
                , setNonSuccess = r.setNonSuccess
                , onSuccess = r.onSuccess
                , onError = Nothing
                , request = r.request
                , showErrorModal = r.showErrorModal
                }
    in
    case action of
        FetchAudienceFolders ->
            fetchWithoutCustomError
                { getState = .audienceFolders
                , setNonSuccess = \val store_ -> { store_ | audienceFolders = val }
                , onSuccess = AudienceRelatedMsg << AudienceFoldersFetched
                , request = XB2.Share.Data.Platform2.getAudienceFolders
                , showErrorModal = True
                }

        FetchQuestion { showErrorModal } questionCode ->
            \config ->
                fetch_
                    { getState = getQuestion questionCode
                    , setNonSuccess =
                        \val store_ ->
                            { store_
                                | questions =
                                    store_.questions
                                        |> Dict.Any.insert questionCode val
                            }
                    , onSuccess = QuestionFetched questionCode
                    , onError = Just <| \b us -> config.msg << QuestionFetchError questionCode b us
                    , request = Labels.getQuestionV2 questionCode
                    , showErrorModal = showErrorModal
                    }
                    config

        FetchAllLocations ->
            fetchWithoutCustomError
                { getState = .locations
                , setNonSuccess = \val store_ -> { store_ | locations = val }
                , onSuccess = LocationsFetched
                , request = Labels.getAllLocationsV2
                , showErrorModal = True
                }

        FetchLocationsByNamespace namespaceCode ->
            fetchWithoutCustomError
                { getState = getLocations namespaceCode
                , setNonSuccess =
                    \val store_ ->
                        let
                            valueToInsert =
                                case val of
                                    Failure (Http.BadStatus 403) ->
                                        Success XB2.Share.Data.Id.emptyDict

                                    _ ->
                                        val
                        in
                        { store_
                            | locationsByNamespace =
                                store_.locationsByNamespace
                                    |> Dict.Any.insert namespaceCode valueToInsert
                        }
                , onSuccess = LocationsByNamespaceFetched namespaceCode
                , request = Labels.getLocationsForNamespace namespaceCode
                , showErrorModal = False
                }

        FetchAllWaves ->
            fetchWithoutCustomError
                { getState = .waves
                , setNonSuccess = \val store_ -> { store_ | waves = val }
                , onSuccess = WavesFetched
                , request = Labels.getAllWavesV2
                , showErrorModal = True
                }

        FetchWavesByNamespace namespaceCode ->
            fetchWithoutCustomError
                { getState = getWaves namespaceCode
                , setNonSuccess =
                    \val store_ ->
                        let
                            valueToInsert =
                                case val of
                                    Failure (Http.BadStatus 403) ->
                                        Success XB2.Share.Data.Id.emptyDict

                                    _ ->
                                        val
                        in
                        { store_
                            | wavesByNamespace =
                                store_.wavesByNamespace
                                    |> Dict.Any.insert namespaceCode valueToInsert
                        }
                , onSuccess = WavesByNamespaceFetched namespaceCode
                , request = Labels.getWavesForNamespaceV2 namespaceCode
                , showErrorModal = False
                }

        FetchDatasetFolders ->
            fetchWithoutCustomError
                { getState = .datasetFoldersTree
                , setNonSuccess = \val store_ -> { store_ | datasetFoldersTree = val }
                , onSuccess = DatasetFoldersFetched
                , request = XB2.Share.Data.Platform2.getDatasetFolders
                , showErrorModal = True
                }

        FetchDatasets ->
            fetchWithoutCustomError
                { getState = .datasets
                , setNonSuccess = \val store_ -> { store_ | datasets = val }
                , onSuccess = DatasetsFetched
                , request = XB2.Share.Data.Platform2.getDatasets
                , showErrorModal = True
                }

        FetchLineage namespaceCode ->
            fetchWithoutCustomError
                { getState =
                    .lineages
                        >> Dict.Any.get namespaceCode
                        >> Maybe.withDefault NotAsked
                , setNonSuccess =
                    \val store_ ->
                        { store_
                            | lineages =
                                store_.lineages
                                    |> Dict.Any.insert namespaceCode val
                        }
                , onSuccess = LineageFetched namespaceCode
                , request = Labels.getLineage namespaceCode
                , showErrorModal = False
                }


storeActionMany : List StoreAction -> Config msg -> Flags -> Store -> ( Store, Cmd msg )
storeActionMany actions config flags store =
    List.foldl
        (\action ( store_, cmds ) ->
            let
                ( newStore, newCmd ) =
                    fetch action config flags store_
            in
            ( newStore, newCmd :: cmds )
        )
        ( store, [] )
        actions
        |> Tuple.mapSecond Cmd.batch


setLocationsForNamespace : Namespace.Code -> List Location -> Store -> Store
setLocationsForNamespace namespaceCode locations store =
    { store
        | locationsByNamespace =
            store.locationsByNamespace
                |> Dict.Any.insert namespaceCode
                    (Store.taggedCollectionLoadedWith .code locations)
        , regionsByNamespace =
            store.regionsByNamespace
                |> Dict.Any.insert namespaceCode
                    (Success <| Labels.groupToRegion locations)
    }


setWavesForNamespace : Namespace.Code -> List Wave -> Store -> Store
setWavesForNamespace namespaceCode waves store =
    { store
        | wavesByNamespace =
            store.wavesByNamespace
                |> Dict.Any.insert namespaceCode
                    (Store.taggedCollectionLoadedWith .code waves)
    }


update : Config msg -> Msg -> Store -> ( Store, Cmd msg )
update config msg store =
    case msg of
        AudienceRelatedMsg (AudienceFoldersFetched folders) ->
            ( { store
                | audienceFolders =
                    Success
                        (Store.collectionToAnyDict
                            folders
                            .id
                            AudienceFolder.idToString
                        )
              }
            , Cmd.none
            )

        AudienceRelatedMsg (AudienceWithExpressionCreated audiences audience) ->
            ( { store | audiences = RemoteData.map (Dict.Any.insert audience.id audience) audiences }
            , Cmd.none
            )

        QuestionFetched questionCode question ->
            ( { store
                | questions =
                    store.questions
                        |> Dict.Any.insert questionCode (Success question)
              }
            , Cmd.none
            )

        QuestionFetchError _ showErrorModal updateStoreFn err ->
            ( store
            , (if showErrorModal then
                config.err updateStoreFn err

               else
                config.errWithoutModal updateStoreFn err
              )
                |> Cmd.perform
            )

        LocationsFetched locations ->
            ( { store
                | locations = Store.taggedCollectionLoadedWith .code locations
                , allRegions = Success <| Labels.groupToRegion locations
              }
            , Cmd.none
            )

        LocationsByNamespaceFetched namespaceCode locations ->
            ( setLocationsForNamespace namespaceCode locations store
            , Cmd.none
            )

        WavesFetched waves ->
            ( { store | waves = Store.taggedCollectionLoadedWith .code waves }, Cmd.none )

        WavesByNamespaceFetched namespaceCode waves ->
            ( setWavesForNamespace namespaceCode waves store
            , Cmd.none
            )

        DatasetFoldersFetched datasetFolders ->
            ( { store | datasetFoldersTree = Success datasetFolders }
            , Cmd.none
            )

        DatasetsFetched datasets ->
            ( { store
                | datasets = Success (Store.collectionToAnyDict datasets .code Dataset.codeToString)
                , datasetsToNamespaces =
                    datasets
                        |> List.map (\ds -> ( ds.code, ds.baseNamespaceCode ))
                        |> BiDict.fromList
                        |> Success
              }
            , Cmd.none
            )

        LineageFetched namespaceCode lineage ->
            ( { store
                | lineages =
                    store.lineages
                        |> Dict.Any.insert namespaceCode (Success lineage)
              }
            , Cmd.none
            )


getQuestion : NamespaceAndQuestionCode -> Store -> WebData Question
getQuestion questionCode store =
    store.questions
        |> Dict.Any.get questionCode
        |> Maybe.withDefault NotAsked


getQuestionMaybe : NamespaceAndQuestionCode -> Store -> Maybe Question
getQuestionMaybe questionCode store =
    getQuestion questionCode store
        |> RemoteData.toMaybe


createAudienceWithExpression :
    Config msg
    -> String
    -> Expression
    -> Flags
    -> Store
    -> ( Store, Cmd msg )
createAudienceWithExpression { msg, err } name expression flags originalStore =
    Store.fetch
        never
        .audiences
        (msg << AudienceRelatedMsg << AudienceWithExpressionCreated originalStore.audiences)
        err
        (XB2.Share.Data.Platform2.createAudienceWithExpression name expression)
        (\store ->
            Maybe.unwrap { store | audiences = Loading }
                (\_ -> { store | audiences = originalStore.audiences })
        )
        flags
        originalStore


getDatapointMaybe : Store -> NamespaceAndQuestionCode -> QuestionAndDatapointCode -> Maybe Datapoint
getDatapointMaybe store questionCode datapointCode =
    getQuestionMaybe questionCode store
        |> Maybe.andThen (.datapoints >> NonemptyList.find (\{ code } -> code == datapointCode))
