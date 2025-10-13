module XB2.CrosstabCellLoader exposing
    ( AfterQueueFinishedCmd
    , Config
    , Model
    , Msg
    , OpenedCellLoaderModal(..)
    , cancelAllLoadingRequests
    , dequeueAndInterpretCommand
    , getAfterAction
    , init
    , interpretCommands
    , isFullyLoaded
    , notLoadedCellCount
    , reloadNotAskedCellsIfFullLoadRequestedWithOriginAndMsg
    , reloadOnlyNeededCellsForSortingWithOriginAndMsg
    , resetRetries
    , setOpenedCellLoaderModal
    , showFullTableLoader
    , update
    , updateAudienceCrosstab
    )

{-| An abstraction of the cell loading events for the
[`AudienceCrosstab`](XB2.Data.AudienceCrosstab#AudienceCrosstab)s.
-}

import AssocSet
import Cmd.Extra as Cmd
import Dict exposing (Dict)
import Dict.Any
import Glue
import Http
import Json.Decode as Decode
import List.Extra as List
import List.NonEmpty as NonemptyList exposing (NonEmpty)
import List.NonEmpty.Zipper as ListZipper
import Maybe.Extra as Maybe
import Queue exposing (Queue)
import RemoteData
import Set.Any
import Task
import Time exposing (Posix)
import XB2.Analytics as Analytics exposing (Event(..))
import XB2.Api.V1.Crosstabs as XBApi
import XB2.Data.Audience.Expression as Expression
    exposing
        ( Expression
        )
import XB2.Data.AudienceCrosstab as ACrosstab
    exposing
        ( AudienceCrosstab
        , AverageColRequestData
        , AverageRowRequestData
        , Cell
        , CellData(..)
        , RequestParams(..)
        , TotalColAverageRowRequestData
        , TotalRowAverageColRequestData
        )
import XB2.Data.AudienceCrosstab.Sort exposing (SortConfig)
import XB2.Data.AudienceItem as AudienceItem exposing (AudienceItem)
import XB2.Data.AudienceItemId as AudienceItemId
import XB2.Data.Average as Average exposing (Average)
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect
    exposing
        ( AudienceParam
        , IntersectResult
        , RequestOrigin
        , XBQueryError
        , xbQueryErrorStringWithoutCodeTranslation
        )
import XB2.Data.Calc.Average as Average exposing (AverageResult)
import XB2.Data.Caption as Caption
import XB2.Data.Suffix as Suffix
import XB2.Data.Zod.Nullish as Nullish
import XB2.Data.Zod.Optional as Optional
import XB2.RemoteData.Tracked as Tracked exposing (RemoteData(..))
import XB2.Router exposing (Route)
import XB2.Share.Analytics.Place exposing (Place)
import XB2.Share.Config exposing (Flags)
import XB2.Share.Data.Core.Error as CoreError
import XB2.Share.Data.Id exposing (IdSet)
import XB2.Share.Data.Labels
    exposing
        ( Location
        , LocationCodeTag
        , Question
        , QuestionAveragesUnit(..)
        , Wave
        , WaveCodeTag
        )
import XB2.Share.Data.Platform2
import XB2.Share.Gwi.Http exposing (Error(..), OtherError(..))
import XB2.Share.Gwi.List as List
import XB2.Share.Store.Platform2
import XB2.Share.Store.Utils as Store
import XB2.Sort
    exposing
        ( Axis(..)
        , AxisSort(..)
        )


type alias Config msg afterAction =
    { msg : Msg -> msg
    , fetchManyP2 : List XB2.Share.Store.Platform2.StoreAction -> msg
    , queryAjaxError : Error XBQueryError -> msg
    , analyticsPlace : Place
    , getAfterQueueMsg : afterAction -> { startTime : Posix, time : Posix } -> msg
    }


maxRequestsLimit : Int
maxRequestsLimit =
    800


{-| ATC-2295 retry functionality. We allow 3 tries for NetworkError / Timeout
errors, after which we give up and keep the Failure (N/A) there.
-}
maxTries : Int
maxTries =
    3


type AfterQueueFinishedCmd afterAction
    = NoCmd
    | WaitingForTime afterAction
    | MeasuredCmd Posix afterAction


type OpenedCellLoaderModal
    = NoCellLoaderModal
    | LoadWithoutProgress
    | LoadWithProgress { currentProgress : Float, totalProgress : Float }


setOpenedCellLoaderModal : OpenedCellLoaderModal -> Model afterAction -> Model afterAction
setOpenedCellLoaderModal openedCellLoaderModal model =
    { model | openedCellLoaderModal = openedCellLoaderModal }


type alias Model afterAction =
    { crosstabCommandsQueue : Queue ACrosstab.Command
    , afterQueueFinishedCmd : AfterQueueFinishedCmd afterAction
    , audienceCrosstab : AudienceCrosstab
    , requestOrigin : RequestOrigin
    , retries : Dict String Int
    , openedCellLoaderModal : OpenedCellLoaderModal
    }


init : AudienceCrosstab -> Model afterAction
init audienceCrosstab =
    { crosstabCommandsQueue = Queue.empty
    , afterQueueFinishedCmd = NoCmd
    , audienceCrosstab = audienceCrosstab
    , requestOrigin = AudienceIntersect.Table
    , retries = Dict.empty
    , openedCellLoaderModal = NoCellLoaderModal
    }


type Msg
    = NoOp
    | CellLoaded
        RequestOrigin
        (IdSet LocationCodeTag)
        (IdSet WaveCodeTag)
        { row : ACrosstab.Key
        , col : ACrosstab.Key
        , base : BaseAudience
        }
        CellData
    | BulkCellsLoaded
        RequestOrigin
        (IdSet LocationCodeTag)
        (IdSet WaveCodeTag)
        BaseAudience
        (List
            { row : ACrosstab.Key
            , col : ACrosstab.Key
            , cellData : CellData
            }
        )
        (List
            { row : AudienceItem
            , col : AudienceItem
            , itemWhichIsNotTotals : AudienceItem
            , cellData : CellData
            }
        )
      -- Like CellLoaded, but for multiple cells at once, including also response with Totals
    | BulkCellIncompatibilitiesLoaded
        (IdSet LocationCodeTag)
        (IdSet WaveCodeTag)
        (List
            { row : ACrosstab.Key
            , col : ACrosstab.Key
            , base : BaseAudience
            , incompatibilities : Tracked.WebData Never XB2.Share.Data.Platform2.Incompatibilities
            }
        )
        (List
            { item : AudienceItem
            , base : BaseAudience
            , incompatibilities : Tracked.WebData Never XB2.Share.Data.Platform2.Incompatibilities
            }
        )
    | TotalsCellLoaded
        RequestOrigin
        (IdSet LocationCodeTag)
        (IdSet WaveCodeTag)
        { col : AudienceItem
        , row : AudienceItem
        }
        { item : AudienceItem, base : BaseAudience }
        CellData
    | CellLoadError (Error XBQueryError)
    | BulkCellsLoadError
        RequestOrigin
        (Error Decode.Error)
        Tracked.TrackerId
        (IdSet LocationCodeTag)
        (IdSet WaveCodeTag)
        BaseAudience
        (List
            { row : ACrosstab.Key
            , col : ACrosstab.Key
            , cellData : CellData
            }
        )
        (List
            { row : AudienceItem
            , col : AudienceItem
            , itemWhichIsNotTotals : AudienceItem
            , cellData : CellData
            }
        )
      -- Unlike CellLoadError, this means the whole bulk load failed, not a single cell inside it
      -- TODO: | BulkCellIncompatibilitiesLoadError (Error Decode.Error)
    | SetStartTimeAndReaload Posix
    | SetStartTimeAndRealoadForSorting (NonEmpty SortConfig) Posix


getAfterAction : Model afterAction -> Maybe afterAction
getAfterAction { afterQueueFinishedCmd } =
    case afterQueueFinishedCmd of
        NoCmd ->
            Nothing

        WaitingForTime afterAction ->
            Just afterAction

        MeasuredCmd _ afterAction ->
            Just afterAction


processAfterQueueCmd : Config msg afterAction -> Model afterAction -> ( Model afterAction, Cmd msg )
processAfterQueueCmd config model =
    let
        noOp =
            config.msg NoOp

        fullyLoadTableMsg afterQueueFinishedCmd =
            Time.now
                |> Task.map
                    (\time ->
                        case afterQueueFinishedCmd of
                            NoCmd ->
                                noOp

                            WaitingForTime afterAction ->
                                config.getAfterQueueMsg afterAction { startTime = time, time = time }

                            MeasuredCmd startTime afterAction ->
                                config.getAfterQueueMsg afterAction { startTime = startTime, time = time }
                    )
                |> Task.attempt (Result.withDefault noOp)

        finalFullyLoadTableMsg =
            case model.afterQueueFinishedCmd of
                NoCmd ->
                    Cmd.none

                WaitingForTime _ ->
                    fullyLoadTableMsg model.afterQueueFinishedCmd

                MeasuredCmd _ _ ->
                    fullyLoadTableMsg model.afterQueueFinishedCmd
    in
    if not <| ACrosstab.isLoading <| currentCrosstab model then
        { model
            | afterQueueFinishedCmd = NoCmd
            , openedCellLoaderModal = NoCellLoaderModal
        }
            |> Cmd.with finalFullyLoadTableMsg

    else
        Cmd.pure model


dequeueAndInterpretCommand :
    Config msg afterAction
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> Model afterAction
    -> ( Model afterAction, Cmd msg )
dequeueAndInterpretCommand config flags p2Store model =
    if Queue.isEmpty model.crosstabCommandsQueue then
        processAfterQueueCmd config model

    else
        case Queue.dequeue model.crosstabCommandsQueue of
            ( Just command, queue ) ->
                { model
                    | crosstabCommandsQueue = queue
                }
                    |> Cmd.pure
                    |> Glue.updateWith Glue.id (interpretCrosstabCommand config flags p2Store command)

            ( Nothing, _ ) ->
                processAfterQueueCmd config model


retryCellLoad :
    Config msg afterAction
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> { row : ACrosstab.Key, col : ACrosstab.Key, base : BaseAudience }
    -> Model afterAction
    -> ( Model afterAction, Cmd msg )
retryCellLoad config flags p2Store key model =
    let
        modelWithRetryIncremented =
            model
                |> incRetryCount (cellToRetryKey key)

        crosstab =
            currentCrosstab modelWithRetryIncremented

        ( newCrosstab, reloadCellsCommands ) =
            crosstab
                |> ACrosstab.forceCellShouldBeLoaded key
                |> ACrosstab.reloadCell key
    in
    { modelWithRetryIncremented
        | crosstabCommandsQueue = List.foldl Queue.enqueue modelWithRetryIncremented.crosstabCommandsQueue reloadCellsCommands
    }
        |> setAudienceCrosstab newCrosstab
        |> Cmd.pure
        |> Glue.updateWith Glue.id (interpretCrosstabCommands config flags p2Store reloadCellsCommands)


retryTotalCellLoad :
    Config msg afterAction
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> ( AudienceItem, BaseAudience )
    -> Model afterAction
    -> ( Model afterAction, Cmd msg )
retryTotalCellLoad config flags p2Store key model =
    let
        modelWithRetryIncremented =
            model
                |> incRetryCount (totalCellToRetryKey key)

        crosstab =
            currentCrosstab modelWithRetryIncremented

        ( newCrosstab, reloadCellsCommands ) =
            crosstab
                |> ACrosstab.forceTotalCellShouldBeLoaded key
                |> ACrosstab.reloadTotalCell key
    in
    { modelWithRetryIncremented
        | crosstabCommandsQueue = List.foldl Queue.enqueue modelWithRetryIncremented.crosstabCommandsQueue reloadCellsCommands
    }
        |> setAudienceCrosstab newCrosstab
        |> Cmd.pure
        |> Glue.updateWith Glue.id (interpretCrosstabCommands config flags p2Store reloadCellsCommands)


incRetryCount : String -> Model afterAction -> Model afterAction
incRetryCount retryKey model =
    { model
        | retries =
            model.retries
                |> Dict.update retryKey
                    (\maybeCount ->
                        case maybeCount of
                            Nothing ->
                                {- Not "maxTries - 1", but "previousTries + 1".

                                   We just don't hold the "have tried once" items
                                   in the dict, as that would be majority of the
                                   cells in the happy case.

                                   If you're calling this function, it means that
                                   you have tried once already and want to retry.
                                   So we're making the try count 2.
                                -}
                                Just 2

                            Just count ->
                                Just (count + 1)
                    )
    }


getActiveWaves : Model afterAction -> IdSet WaveCodeTag
getActiveWaves =
    .audienceCrosstab >> ACrosstab.getActiveWaves


getActiveLocations : Model afterAction -> IdSet LocationCodeTag
getActiveLocations =
    .audienceCrosstab >> ACrosstab.getActiveLocations


wavesAndLocations : XB2.Share.Store.Platform2.Store -> Model afterAction -> ( List Wave, List Location )
wavesAndLocations p2Store model =
    ( Store.getByIds p2Store.waves <| Set.Any.toList <| getActiveWaves model
    , Store.getByIds p2Store.locations <| Set.Any.toList <| getActiveLocations model
    )


{-| Essentially, tracking the _default_ base audience in a special way.
-}
prepareBaseForTracking : BaseAudience -> BaseAudience
prepareBaseForTracking baseAudience =
    if BaseAudience.isDefault baseAudience then
        baseAudience
            |> BaseAudience.setCaption
                (Caption.fromAudience
                    { audience = "Default"
                    , parent = Nothing
                    }
                )

    else
        baseAudience


trackNAErrorForCellBasedOnRequestOrigin : Config msg afterAction -> Route -> RequestOrigin -> Flags -> CellData -> String -> XB2.Share.Store.Platform2.Store -> Model afterAction -> ( Model afterAction, Cmd msg )
trackNAErrorForCellBasedOnRequestOrigin config route requestOrigin flags cellData key store model =
    let
        trackFailure result =
            case ( result, requestOrigin ) of
                ( Failure error, AudienceIntersect.Table ) ->
                    let
                        ( waves, locations ) =
                            wavesAndLocations store model
                    in
                    ( model
                    , NAIntersection
                        { bases =
                            model.audienceCrosstab
                                |> ACrosstab.getBaseAudiences
                                |> ListZipper.toNonEmpty
                                |> NonemptyList.map prepareBaseForTracking
                                |> NonemptyList.toList
                        , crosstab = ACrosstab.getCrosstab model.audienceCrosstab
                        , locations = locations
                        , waves = waves
                        , extraParams =
                            { queryError = error
                            , retryCount =
                                Dict.get key model.retries
                                    |> Maybe.withDefault 0
                            }
                        }
                        |> Analytics.trackEvent flags route config.analyticsPlace
                    )

                _ ->
                    Cmd.pure model
    in
    case cellData of
        AvAData data ->
            trackFailure data.data

        AverageData data ->
            trackFailure data


{-| Appends the row, col and baseAudience into a hashed `String` for storing purposes.
-}
cellToRetryKey :
    { row : ACrosstab.Key
    , col : ACrosstab.Key
    , base : BaseAudience
    }
    -> String
cellToRetryKey { row, col, base } =
    [ AudienceItem.getIdString row.item
    , AudienceItem.getIdString col.item
    , AudienceItemId.toString <| BaseAudience.getId base
    ]
        |> String.join "|"


totalCellToRetryKey : ( AudienceItem, BaseAudience ) -> String
totalCellToRetryKey ( item, base ) =
    [ AudienceItem.getIdString item
    , AudienceItemId.toString <| BaseAudience.getId base
    ]
        |> String.join "|"


currentCrosstab : Model afterAction -> AudienceCrosstab
currentCrosstab =
    .audienceCrosstab


updateAudienceCrosstab : (AudienceCrosstab -> AudienceCrosstab) -> Model afterAction -> Model afterAction
updateAudienceCrosstab fn model =
    { model | audienceCrosstab = fn model.audienceCrosstab }


setAudienceCrosstab : AudienceCrosstab -> Model afterAction -> Model afterAction
setAudienceCrosstab audienceCrosstab =
    updateAudienceCrosstab (always audienceCrosstab)


canTryAgain : String -> Model afterAction -> Bool
canTryAgain retryKey { retries } =
    let
        triesDone =
            Dict.get retryKey retries
                |> Maybe.withDefault 1
    in
    triesDone < maxTries


{-| Checks if a cell has a Tracked.Failure status for a retry.
-}
shouldRetry : CellData -> Bool
shouldRetry webdata =
    let
        checkIfShouldRetry response =
            case response of
                Failure Timeout ->
                    True

                Failure NetworkError ->
                    True

                Failure (GenericError _ _ CoreError.GatewayTimeout) ->
                    True

                Failure (GenericError _ _ CoreError.InternalServerError) ->
                    True

                Failure (GenericError _ _ (CoreError.UnknownError _)) ->
                    True

                _ ->
                    False
    in
    case webdata of
        AvAData { data } ->
            checkIfShouldRetry data

        AverageData data ->
            checkIfShouldRetry data


update :
    Config msg afterAction
    -> Route
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> Msg
    -> Model afterAction
    -> ( Model afterAction, Cmd msg )
update config route flags p2Store msg model =
    let
        updateACIncompatibilitiesBulk :
            IdSet LocationCodeTag
            -> IdSet WaveCodeTag
            -> (ACrosstab.Incompatibilities -> AudienceCrosstab -> AudienceCrosstab)
            -> Tracked.WebData Never XB2.Share.Data.Platform2.Incompatibilities
            -> ( Model afterAction, Cmd msg )
            -> ( Model afterAction, Cmd msg )
        updateACIncompatibilitiesBulk locationCodes waveIds inserter value ( modelAfterAction, cmds ) =
            let
                processedValue =
                    Tracked.map
                        (Dict.Any.values
                            >> List.filterMap
                                (\d ->
                                    Store.get p2Store.locations d.locationCode
                                        |> Maybe.map
                                            (\location ->
                                                { location = location
                                                , waves =
                                                    Set.Any.toList d.waveCodes
                                                        |> List.filterMap
                                                            (Store.get p2Store.waves)
                                                }
                                            )
                                )
                        )
                        value

                insertData :
                    ( Model afterAction, Cmd msg )
                    -> ( Model afterAction, Cmd msg )
                insertData ( modelAfterAction_, cmds_ ) =
                    if
                        locationCodes
                            == getActiveLocations modelAfterAction_
                            && waveIds
                            == getActiveWaves modelAfterAction_
                    then
                        ( updateAudienceCrosstab (inserter processedValue)
                            modelAfterAction_
                        , cmds_
                        )

                    else
                        ( modelAfterAction_, cmds_ )
            in
            ( modelAfterAction, cmds )
                |> insertData
                |> Glue.updateWith Glue.id
                    (dequeueAndInterpretCommand config
                        flags
                        p2Store
                    )
    in
    case msg of
        NoOp ->
            Cmd.pure model

        CellLoaded requestOrigin locationCodes waveIds key value ->
            let
                existingCell : Cell
                existingCell =
                    currentCrosstab model
                        |> ACrosstab.value key

                insertCell : Model afterAction -> ( Model afterAction, Cmd msg )
                insertCell model_ =
                    if locationCodes == getActiveLocations model_ && waveIds == getActiveWaves model_ then
                        if shouldRetry value && canTryAgain (cellToRetryKey key) model_ then
                            model_
                                |> retryCellLoad config flags p2Store key

                        else if not (ACrosstab.isCellSuccess existingCell && ACrosstab.isCellDataFailure value) then
                            model_
                                |> updateAudienceCrosstab (ACrosstab.insertCrosstabCell key value)
                                |> Cmd.pure

                        else
                            model_
                                |> Cmd.pure

                    else
                        model_
                            |> Cmd.pure
            in
            model
                |> insertCell
                |> Glue.updateWith Glue.id (trackNAErrorForCellBasedOnRequestOrigin config route requestOrigin flags value (cellToRetryKey key) p2Store)
                |> Glue.updateWith Glue.id
                    (dequeueAndInterpretCommand config
                        flags
                        p2Store
                    )

        BulkCellsLoaded requestOrigin locationCodes waveIds baseAudience crosstabTableCells crosstabTotalCells ->
            -- TODO: This is a bit of a mess, investigate to make it cleaner.
            -- `crosstabTableCells` are the values that will be inserted inside the `crosstabTable` field of the `AudienceCrosstab`.
            -- `crosstabTotalCells` are the values that will be inserted inside the `totals` field of the `AudienceCrosstab`.
            -- Yup, they work differently...
            let
                insertCell :
                    ( Model afterAction, List (Cmd msg) )
                    -> CellData
                    -> { row : ACrosstab.Key, col : ACrosstab.Key, base : BaseAudience }
                    -> ( Model afterAction, List (Cmd msg) )
                insertCell ( modelFolded, cmdsFolded ) value key =
                    let
                        existingCell : Cell
                        existingCell =
                            currentCrosstab modelFolded
                                |> ACrosstab.value key
                    in
                    -- If locations/waves are the same as the active ones
                    if locationCodes == getActiveLocations modelFolded && waveIds == getActiveWaves modelFolded then
                        -- If the cell has a Failure status and it hasn't surpassed the limit of `maxTries`
                        if shouldRetry value && canTryAgain (cellToRetryKey key) modelFolded then
                            let
                                ( modelAfterRetryingCellLoad, retryCellLoadCmds ) =
                                    -- Retry a cell load setting its .shouldBeLoaded to `True` and tracking the NA error in case it exists.
                                    modelFolded
                                        |> retryCellLoad config flags p2Store key

                                ( modelAfterRetryingCellLoadAndTrackingNA, trackNACmds ) =
                                    -- Track if it is equal to a Failure status
                                    modelAfterRetryingCellLoad
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (cellToRetryKey key)
                                            p2Store
                            in
                            ( modelAfterRetryingCellLoadAndTrackingNA
                            , retryCellLoadCmds :: trackNACmds :: cmdsFolded
                            )

                        else if not (ACrosstab.isCellSuccess existingCell && ACrosstab.isCellDataFailure value) then
                            let
                                ( modelAfterRetryingCellLoadAndTrackingNA, trackNACmds ) =
                                    -- If the existing cell isn't already loaded and the response is not a failure then we insert it into the crosstab.
                                    updateAudienceCrosstab (ACrosstab.insertCrosstabCell key value) modelFolded
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (cellToRetryKey key)
                                            p2Store
                            in
                            ( modelAfterRetryingCellLoadAndTrackingNA
                            , trackNACmds :: cmdsFolded
                            )

                        else
                            let
                                -- Otherwise we just don't care and the response and check for possible NAs
                                ( modelAfterRetryingCellLoadAndTrackingNA, trackNACmds ) =
                                    modelFolded
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (cellToRetryKey key)
                                            p2Store
                            in
                            ( modelAfterRetryingCellLoadAndTrackingNA
                            , trackNACmds :: cmdsFolded
                            )

                    else
                        let
                            -- If the locations/waves are not the same as the active ones then the data is invalid and we don't care about the response.
                            ( modelAfterRetryingCellLoadAndTrackingNA, trackNACmds ) =
                                modelFolded
                                    |> trackNAErrorForCellBasedOnRequestOrigin config
                                        route
                                        requestOrigin
                                        flags
                                        value
                                        (cellToRetryKey key)
                                        p2Store
                        in
                        ( modelAfterRetryingCellLoadAndTrackingNA
                        , trackNACmds :: cmdsFolded
                        )

                insertTotalCell :
                    ( Model afterAction, List (Cmd msg) )
                    -> CellData
                    -> { row : AudienceItem, col : AudienceItem, item : AudienceItem }
                    -> ( Model afterAction, List (Cmd msg) )
                insertTotalCell ( modelFolded, cmdsFolded ) value { row, col, item } =
                    let
                        existingCell : Cell
                        existingCell =
                            currentCrosstab modelFolded
                                |> ACrosstab.valueForAudienceItem
                                    { row = row
                                    , col = col
                                    , base = baseAudience
                                    }

                        key_ : ( AudienceItem, BaseAudience )
                        key_ =
                            ( item, baseAudience )
                    in
                    -- If locations/waves are the same as the active ones
                    if locationCodes == getActiveLocations modelFolded && waveIds == getActiveWaves modelFolded then
                        -- If the cell has a Failure status and it hasn't surpassed the limit of `maxTries`
                        if shouldRetry value && canTryAgain (totalCellToRetryKey key_) modelFolded then
                            let
                                ( modelAfterRetryingTotalCellLoad, retryTotalCellLoadCmds ) =
                                    -- Retry a cell load setting its .shouldBeLoaded to `True` and tracking the NA error in case it exists.
                                    modelFolded
                                        |> retryTotalCellLoad config flags p2Store key_

                                ( modelAfterRetryingTotalCellLoadAndTrackingNA, trackNACmds ) =
                                    -- Track if it is equal to a Failure status
                                    modelAfterRetryingTotalCellLoad
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (totalCellToRetryKey key_)
                                            p2Store
                            in
                            ( modelAfterRetryingTotalCellLoadAndTrackingNA
                            , retryTotalCellLoadCmds :: trackNACmds :: cmdsFolded
                            )

                        else if not (ACrosstab.isCellSuccess existingCell && ACrosstab.isCellDataFailure value) then
                            let
                                ( modelAfterRetryingTotalCellLoadAndTrackingNA, trackNACmds ) =
                                    -- If the existing cell isn't already loaded and the response is not a failure then we insert it into the crosstab.
                                    updateAudienceCrosstab (ACrosstab.insertTotalsCell item baseAudience value) modelFolded
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (totalCellToRetryKey key_)
                                            p2Store
                            in
                            ( modelAfterRetryingTotalCellLoadAndTrackingNA
                            , trackNACmds :: cmdsFolded
                            )

                        else
                            let
                                -- Otherwise we just don't care and the response and check for possible NAs
                                ( modelAfterRetryingTotalCellLoadAndTrackingNA, trackNACmds ) =
                                    modelFolded
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (totalCellToRetryKey key_)
                                            p2Store
                            in
                            ( modelAfterRetryingTotalCellLoadAndTrackingNA
                            , trackNACmds :: cmdsFolded
                            )

                    else
                        let
                            -- Otherwise we just don't care and the response and check for possible NAs
                            ( modelAfterRetryingTotalCellLoadAndTrackingNA, trackNACmds ) =
                                modelFolded
                                    |> trackNAErrorForCellBasedOnRequestOrigin config
                                        route
                                        requestOrigin
                                        flags
                                        value
                                        (totalCellToRetryKey key_)
                                        p2Store
                        in
                        ( modelAfterRetryingTotalCellLoadAndTrackingNA
                        , trackNACmds :: cmdsFolded
                        )
            in
            -- We first add the table cells and commands to the model and then we add the total ones.
            List.foldl
                (\{ row, col, cellData } modelAndCmdsAcc ->
                    insertCell modelAndCmdsAcc
                        cellData
                        { row = row
                        , col = col
                        , base = baseAudience
                        }
                )
                ( model, [ Cmd.none ] )
                crosstabTableCells
                |> (\crosstabTableWithCellsInsertedAndCmds ->
                        List.foldl
                            (\{ row, col, itemWhichIsNotTotals, cellData } modelAndCmdsAcc ->
                                insertTotalCell modelAndCmdsAcc
                                    cellData
                                    { row = row
                                    , col = col
                                    , item = itemWhichIsNotTotals
                                    }
                            )
                            crosstabTableWithCellsInsertedAndCmds
                            crosstabTotalCells
                            -- Batch all the commands into a large one to avoid stack overflow issue inside the compiler (https://github.com/elm/core/issues/1123).
                            |> Tuple.mapSecond Cmd.batch
                            |> Glue.updateWith Glue.id
                                (dequeueAndInterpretCommand config
                                    flags
                                    p2Store
                                )
                   )

        BulkCellIncompatibilitiesLoaded locationCodes waveCodes incompatibilitiesPerCell totalIncompatibilities ->
            -- TODO: Make it stack safe with tail call optimization.
            List.foldl
                (\{ row, col, base, incompatibilities } modelAndCmdsAcc ->
                    updateACIncompatibilitiesBulk locationCodes
                        waveCodes
                        (ACrosstab.insertIncompatibilities
                            { row = row, col = col, base = base }
                        )
                        incompatibilities
                        modelAndCmdsAcc
                )
                ( model, Cmd.none )
                incompatibilitiesPerCell
                |> (\crosstabWithIncompatibilitiesInserted ->
                        List.foldl
                            (\{ item, base, incompatibilities } modelAndCmdsAcc ->
                                updateACIncompatibilitiesBulk locationCodes
                                    waveCodes
                                    (ACrosstab.insertTotalIncompatibilities
                                        item
                                        base
                                    )
                                    incompatibilities
                                    modelAndCmdsAcc
                            )
                            crosstabWithIncompatibilitiesInserted
                            totalIncompatibilities
                   )

        TotalsCellLoaded requestOrigin locationCodes waveIds { col, row } { item, base } value ->
            let
                key_ : ( AudienceItem, BaseAudience )
                key_ =
                    ( item, base )

                existingCell : Cell
                existingCell =
                    currentCrosstab model
                        |> ACrosstab.valueForAudienceItem
                            { row = row
                            , col = col
                            , base = base
                            }

                insertCell : Model afterAction -> ( Model afterAction, Cmd msg )
                insertCell model_ =
                    if locationCodes == getActiveLocations model_ && waveIds == getActiveWaves model_ then
                        if shouldRetry value && canTryAgain (totalCellToRetryKey key_) model_ then
                            model_
                                |> retryTotalCellLoad config flags p2Store key_

                        else if not (ACrosstab.isCellSuccess existingCell && ACrosstab.isCellDataFailure value) then
                            model_
                                |> updateAudienceCrosstab (ACrosstab.insertTotalsCell item base value)
                                |> Cmd.pure

                        else
                            model_
                                |> Cmd.pure

                    else
                        model_
                            |> Cmd.pure
            in
            model
                |> insertCell
                |> Glue.updateWith Glue.id (trackNAErrorForCellBasedOnRequestOrigin config route requestOrigin flags value (totalCellToRetryKey key_) p2Store)
                |> Glue.updateWith Glue.id
                    (dequeueAndInterpretCommand config
                        flags
                        p2Store
                    )

        CellLoadError err ->
            model
                |> dequeueAndInterpretCommand config flags p2Store
                |> Cmd.addTrigger (config.queryAjaxError err)

        BulkCellsLoadError requestOrigin err trackerId locationCodes waveIds baseAudience crosstabTableCells crosstabTotalCells ->
            -- TODO: This is a bit of a mess, investigate to make it cleaner. It is a duplicate from the above BulkCellsLoaded.
            -- `crosstabTableCells` are the values that will be inserted inside the `crosstabTable` field of the `AudienceCrosstab`.
            -- `crosstabTotalCells` are the values that will be inserted inside the `totals` field of the `AudienceCrosstab`.
            -- Yup, they work differently...
            let
                insertCell :
                    ( Model afterAction, List (Cmd msg) )
                    -> CellData
                    -> { row : ACrosstab.Key, col : ACrosstab.Key, base : BaseAudience }
                    -> ( Model afterAction, List (Cmd msg) )
                insertCell ( modelFolded, cmdsFolded ) value key =
                    let
                        existingCell : Cell
                        existingCell =
                            currentCrosstab modelFolded
                                |> ACrosstab.value key
                    in
                    -- If locations/waves are the same as the active ones
                    if locationCodes == getActiveLocations modelFolded && waveIds == getActiveWaves modelFolded then
                        -- If the cell has a Failure status and it hasn't surpassed the limit of `maxTries`
                        if shouldRetry value && canTryAgain (cellToRetryKey key) modelFolded then
                            let
                                ( modelAfterRetryingCellLoad, retryCellLoadCmds ) =
                                    -- Retry a cell load setting its .shouldBeLoaded to `True` and tracking the NA error in case it exists.
                                    modelFolded
                                        |> retryCellLoad config flags p2Store key

                                ( modelAfterRetryingCellLoadAndTrackingNA, trackNACmds ) =
                                    -- Track if it is equal to a Failure status
                                    modelAfterRetryingCellLoad
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (cellToRetryKey key)
                                            p2Store
                            in
                            ( modelAfterRetryingCellLoadAndTrackingNA
                            , retryCellLoadCmds :: trackNACmds :: cmdsFolded
                            )

                        else if not (ACrosstab.isCellSuccess existingCell && ACrosstab.isCellDataFailure value) then
                            let
                                ( modelAfterRetryingCellLoadAndTrackingNA, trackNACmds ) =
                                    -- If the existing cell isn't already loaded and the response is not a failure then we insert it into the crosstab.
                                    updateAudienceCrosstab (ACrosstab.insertCrosstabCell key value) modelFolded
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (cellToRetryKey key)
                                            p2Store
                            in
                            ( modelAfterRetryingCellLoadAndTrackingNA
                            , trackNACmds :: cmdsFolded
                            )

                        else
                            let
                                -- Otherwise we just don't care and the response and check for possible NAs
                                ( modelAfterRetryingCellLoadAndTrackingNA, trackNACmds ) =
                                    modelFolded
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (cellToRetryKey key)
                                            p2Store
                            in
                            ( modelAfterRetryingCellLoadAndTrackingNA
                            , trackNACmds :: cmdsFolded
                            )

                    else
                        let
                            -- If the locations/waves are not the same as the active ones then the data is invalid and we don't care about the response.
                            ( modelAfterRetryingCellLoadAndTrackingNA, trackNACmds ) =
                                modelFolded
                                    |> trackNAErrorForCellBasedOnRequestOrigin config
                                        route
                                        requestOrigin
                                        flags
                                        value
                                        (cellToRetryKey key)
                                        p2Store
                        in
                        ( modelAfterRetryingCellLoadAndTrackingNA
                        , trackNACmds :: cmdsFolded
                        )

                insertTotalCell :
                    ( Model afterAction, List (Cmd msg) )
                    -> CellData
                    -> { row : AudienceItem, col : AudienceItem, item : AudienceItem }
                    -> ( Model afterAction, List (Cmd msg) )
                insertTotalCell ( modelFolded, cmdsFolded ) value { row, col, item } =
                    let
                        existingCell : Cell
                        existingCell =
                            currentCrosstab modelFolded
                                |> ACrosstab.valueForAudienceItem
                                    { row = row
                                    , col = col
                                    , base = baseAudience
                                    }

                        key_ : ( AudienceItem, BaseAudience )
                        key_ =
                            ( item, baseAudience )
                    in
                    -- If locations/waves are the same as the active ones
                    if locationCodes == getActiveLocations modelFolded && waveIds == getActiveWaves modelFolded then
                        -- If the cell has a Failure status and it hasn't surpassed the limit of `maxTries`
                        if shouldRetry value && canTryAgain (totalCellToRetryKey key_) modelFolded then
                            let
                                ( modelAfterRetryingTotalCellLoad, retryTotalCellLoadCmds ) =
                                    -- Retry a cell load setting its .shouldBeLoaded to `True` and tracking the NA error in case it exists.
                                    modelFolded
                                        |> retryTotalCellLoad config flags p2Store key_

                                ( modelAfterRetryingTotalCellLoadAndTrackingNA, trackNACmds ) =
                                    -- Track if it is equal to a Failure status
                                    modelAfterRetryingTotalCellLoad
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (totalCellToRetryKey key_)
                                            p2Store
                            in
                            ( modelAfterRetryingTotalCellLoadAndTrackingNA
                            , retryTotalCellLoadCmds :: trackNACmds :: cmdsFolded
                            )

                        else if not (ACrosstab.isCellSuccess existingCell && ACrosstab.isCellDataFailure value) then
                            let
                                ( modelAfterRetryingTotalCellLoadAndTrackingNA, trackNACmds ) =
                                    -- If the existing cell isn't already loaded and the response is not a failure then we insert it into the crosstab.
                                    updateAudienceCrosstab (ACrosstab.insertTotalsCell item baseAudience value) modelFolded
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (totalCellToRetryKey key_)
                                            p2Store
                            in
                            ( modelAfterRetryingTotalCellLoadAndTrackingNA
                            , trackNACmds :: cmdsFolded
                            )

                        else
                            let
                                -- Otherwise we just don't care and the response and check for possible NAs
                                ( modelAfterRetryingTotalCellLoadAndTrackingNA, trackNACmds ) =
                                    modelFolded
                                        |> trackNAErrorForCellBasedOnRequestOrigin config
                                            route
                                            requestOrigin
                                            flags
                                            value
                                            (totalCellToRetryKey key_)
                                            p2Store
                            in
                            ( modelAfterRetryingTotalCellLoadAndTrackingNA
                            , trackNACmds :: cmdsFolded
                            )

                    else
                        let
                            -- Otherwise we just don't care and the response and check for possible NAs
                            ( modelAfterRetryingTotalCellLoadAndTrackingNA, trackNACmds ) =
                                modelFolded
                                    |> trackNAErrorForCellBasedOnRequestOrigin config
                                        route
                                        requestOrigin
                                        flags
                                        value
                                        (totalCellToRetryKey key_)
                                        p2Store
                        in
                        ( modelAfterRetryingTotalCellLoadAndTrackingNA
                        , trackNACmds :: cmdsFolded
                        )

                xbQueryError : Error XBQueryError
                xbQueryError =
                    XB2.Share.Gwi.Http.CustomError trackerId
                        (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                        (AudienceIntersect.InvalidQuery
                            (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                        )
            in
            -- We first add the table cells and commands to the model and then we add the total ones.
            List.foldl
                (\{ row, col, cellData } modelAndCmdsAcc ->
                    insertCell modelAndCmdsAcc
                        cellData
                        { row = row
                        , col = col
                        , base = baseAudience
                        }
                )
                ( model, [ Cmd.none ] )
                crosstabTableCells
                |> (\crosstabTableWithCellsInsertedAndCmds ->
                        List.foldl
                            (\{ row, col, itemWhichIsNotTotals, cellData } modelAndCmdsAcc ->
                                insertTotalCell modelAndCmdsAcc
                                    cellData
                                    { row = row
                                    , col = col
                                    , item = itemWhichIsNotTotals
                                    }
                            )
                            crosstabTableWithCellsInsertedAndCmds
                            crosstabTotalCells
                            -- Batch all the commands into a large one to avoid stack overflow issue inside the compiler (https://github.com/elm/core/issues/1123).
                            |> Tuple.mapSecond Cmd.batch
                            |> Glue.updateWith Glue.id
                                (dequeueAndInterpretCommand config
                                    flags
                                    p2Store
                                )
                   )
                |> Glue.updateWith Glue.id
                    (dequeueAndInterpretCommand config
                        flags
                        p2Store
                    )
                |> Cmd.addTrigger (config.queryAjaxError xbQueryError)

        SetStartTimeAndReaload startTime ->
            { model
                | afterQueueFinishedCmd =
                    case model.afterQueueFinishedCmd of
                        NoCmd ->
                            NoCmd

                        WaitingForTime aqfMsg ->
                            MeasuredCmd startTime aqfMsg

                        MeasuredCmd _ _ ->
                            model.afterQueueFinishedCmd
            }
                |> reloadNotAskedCellsIfFullLoadRequested config flags p2Store

        SetStartTimeAndRealoadForSorting sortConfigs startTime ->
            { model
                | afterQueueFinishedCmd =
                    case model.afterQueueFinishedCmd of
                        NoCmd ->
                            NoCmd

                        WaitingForTime aqfMsg ->
                            MeasuredCmd startTime aqfMsg

                        MeasuredCmd _ _ ->
                            model.afterQueueFinishedCmd
            }
                |> reloadOnlyNeededCellsForSorting config flags p2Store sortConfigs


handleCellLoadResponse : Config msg afterAction -> (Result (Error XBQueryError) a -> msg) -> Result (Error XBQueryError) a -> msg
handleCellLoadResponse config toTrackedMsg response =
    case response of
        Err err ->
            case err of
                XB2.Share.Gwi.Http.BadStatus metadata _ ->
                    if metadata.statusCode == 401 then
                        config.msg <| CellLoadError err

                    else
                        toTrackedMsg response

                _ ->
                    toTrackedMsg response

        Ok _ ->
            toTrackedMsg response


type alias BulkAvARequestData =
    { rows : List { id : AudienceItemId.AudienceItemId, expression : Expression, key : ACrosstab.Key }
    , cols : List { id : AudienceItemId.AudienceItemId, expression : Expression, key : ACrosstab.Key }
    , locations : IdSet LocationCodeTag
    , waves : IdSet WaveCodeTag
    , maybeBaseAudience : Maybe BaseAudience
    , requestOrigin : AudienceIntersect.RequestOrigin
    , flags : XB2.Share.Config.Flags
    , trackerId : Tracked.TrackerId
    }


sendBulkAvARequest :
    { config : Config msg afterAction
    , trackedToMsg :
        Tracked.WebData
            Decode.Error
            (List AudienceIntersect.BulkIntersectionResponse)
        -> Msg
    }
    -> BulkAvARequestData
    -> Cmd msg
sendBulkAvARequest triggers requestData =
    let
        bulkParamsBaseAudience : AudienceIntersect.BaseAudienceParam
        bulkParamsBaseAudience =
            case requestData.maybeBaseAudience of
                Just baseAudience ->
                    AudienceIntersect.Base baseAudience

                Nothing ->
                    AudienceIntersect.DefaultBase

        toTrackedMsg :
            Result (Error Decode.Error) (List AudienceIntersect.BulkIntersectionResponse)
            -> msg
        toTrackedMsg result =
            result
                |> Tracked.fromResult
                |> triggers.trackedToMsg
                |> triggers.config.msg
    in
    AudienceIntersect.postCrosstab
        { flags = requestData.flags
        , requestOrigin = requestData.requestOrigin
        , trackerId = requestData.trackerId
        , bulkParams =
            { rows =
                List.map
                    (\{ id, expression } ->
                        { id = id
                        , expression = expression
                        }
                    )
                    requestData.rows
            , columns =
                List.map
                    (\{ id, expression } ->
                        { id = id
                        , expression = expression
                        }
                    )
                    requestData.cols
            , baseAudience = bulkParamsBaseAudience
            , locations = Set.Any.toList requestData.locations
            , waves = Set.Any.toList requestData.waves
            }
        }
        |> Cmd.map (handleBulkCellsLoadResponse triggers.config requestData toTrackedMsg)


handleBulkCellsLoadResponse :
    Config msg afterAction
    -> BulkAvARequestData
    -> (Result (Error Decode.Error) a -> msg)
    -> Result (Error Decode.Error) a
    -> msg
handleBulkCellsLoadResponse config requestData toTrackedMsg response =
    case response of
        Err err ->
            let
                cartesian xs ys =
                    List.fastConcatMap
                        (\x -> List.map (\y -> ( x, y )) ys)
                        xs

                cartesianProductOfKeys =
                    cartesian
                        (Nothing :: List.map Just requestData.rows)
                        (Nothing :: List.map Just requestData.cols)

                crosstabCells :
                    List
                        { row : ACrosstab.Key
                        , col : ACrosstab.Key
                        , cellData : CellData
                        }
                crosstabCells =
                    cartesianProductOfKeys
                        |> List.filterMap
                            (\( row, col ) ->
                                case ( row, col ) of
                                    ( Nothing, Nothing ) ->
                                        Nothing

                                    ( Just _, Nothing ) ->
                                        Nothing

                                    ( Nothing, Just _ ) ->
                                        Nothing

                                    ( Just row_, Just col_ ) ->
                                        Just
                                            { row = row_.key
                                            , col = col_.key
                                            , cellData =
                                                AvAData
                                                    { data =
                                                        Tracked.Failure
                                                            (XB2.Share.Gwi.Http.CustomError requestData.trackerId
                                                                (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                                                                (AudienceIntersect.InvalidQuery
                                                                    (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                                                                )
                                                            )
                                                    , incompatibilities = Tracked.NotAsked
                                                    }
                                            }
                            )

                crosstabTotals :
                    List
                        { row : AudienceItem
                        , col : AudienceItem
                        , itemWhichIsNotTotals : AudienceItem
                        , cellData : CellData
                        }
                crosstabTotals =
                    cartesianProductOfKeys
                        |> List.filterMap
                            (\( row, col ) ->
                                case ( row, col ) of
                                    ( Nothing, Nothing ) ->
                                        Just
                                            { row = AudienceItem.totalItem
                                            , col = AudienceItem.totalItem
                                            , itemWhichIsNotTotals = AudienceItem.totalItem
                                            , cellData =
                                                AvAData
                                                    { data =
                                                        Tracked.Failure
                                                            (XB2.Share.Gwi.Http.CustomError requestData.trackerId
                                                                (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                                                                (AudienceIntersect.InvalidQuery
                                                                    (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                                                                )
                                                            )
                                                    , incompatibilities = Tracked.NotAsked
                                                    }
                                            }

                                    ( Just row_, Nothing ) ->
                                        Just
                                            { row = row_.key.item
                                            , col = AudienceItem.totalItem
                                            , itemWhichIsNotTotals = row_.key.item
                                            , cellData =
                                                AvAData
                                                    { data =
                                                        Tracked.Failure
                                                            (XB2.Share.Gwi.Http.CustomError requestData.trackerId
                                                                (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                                                                (AudienceIntersect.InvalidQuery
                                                                    (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                                                                )
                                                            )
                                                    , incompatibilities = Tracked.NotAsked
                                                    }
                                            }

                                    ( Nothing, Just col_ ) ->
                                        Just
                                            { row = AudienceItem.totalItem
                                            , col = col_.key.item
                                            , itemWhichIsNotTotals = col_.key.item
                                            , cellData =
                                                AvAData
                                                    { data =
                                                        Tracked.Failure
                                                            (XB2.Share.Gwi.Http.CustomError requestData.trackerId
                                                                (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                                                                (AudienceIntersect.InvalidQuery
                                                                    (XB2.Share.Gwi.Http.errorToString Decode.errorToString err)
                                                                )
                                                            )
                                                    , incompatibilities = Tracked.NotAsked
                                                    }
                                            }

                                    ( Just _, Just _ ) ->
                                        Nothing
                            )
            in
            config.msg <|
                BulkCellsLoadError requestData.requestOrigin
                    err
                    requestData.trackerId
                    requestData.locations
                    requestData.waves
                    (Maybe.withDefault BaseAudience.default requestData.maybeBaseAudience)
                    crosstabCells
                    crosstabTotals

        Ok _ ->
            toTrackedMsg response


{-| Helper function inside the bulk API response logic to prepare for crosstab table cell
insertion. Meant to be used alongside a `List.filterMap` for the Maybe values.
-}
bulkIntersectionResponseToMaybeRowColData :
    { rows : List ACrosstab.Key
    , cols : List ACrosstab.Key
    , trackerId : Tracked.TrackerId
    }
    -> AudienceIntersect.BulkIntersectionResponse
    -> Maybe { row : ACrosstab.Key, col : ACrosstab.Key, cellData : CellData }
bulkIntersectionResponseToMaybeRowColData params response =
    case response of
        AudienceIntersect.BulkIntersectionSuccess data ->
            case
                ( List.find
                    (\key ->
                        AudienceItem.getIdString key.item == data.audiences.row.id
                    )
                    params.rows
                , List.find
                    (\key ->
                        AudienceItem.getIdString key.item == data.audiences.col.id
                    )
                    params.cols
                )
            of
                -- If both audience items from the response are found in the crosstab then we prepare the data for insertion.
                ( Just row, Just col ) ->
                    Just
                        { row = row
                        , col = col
                        , cellData =
                            AvAData
                                { data =
                                    Tracked.Success
                                        { intersection =
                                            { size = data.intersection.size
                                            , sample = data.intersection.sample
                                            , index = data.intersection.index
                                            }
                                        , audiences =
                                            { row =
                                                { id = data.audiences.row.id
                                                , intersectPercentage =
                                                    data.audiences.row.intersectPercentage
                                                , sample = data.audiences.row.sample
                                                , size = data.audiences.row.size
                                                }
                                            , col =
                                                { id = data.audiences.col.id
                                                , intersectPercentage =
                                                    data.audiences.col.intersectPercentage
                                                , sample = data.audiences.col.sample
                                                , size = data.audiences.col.size
                                                }
                                            }
                                        , stretching = Nothing
                                        }
                                , incompatibilities = Tracked.NotAsked
                                }
                        }

                -- For any other case where we don't have both items then it means the response was somehow invalid.
                ( Nothing, Nothing ) ->
                    Nothing

                ( Just _, Nothing ) ->
                    Nothing

                ( Nothing, Just _ ) ->
                    Nothing

        AudienceIntersect.BulkQueryError error ->
            case
                ( List.find
                    (\key ->
                        AudienceItem.getIdString key.item == error.rowId
                    )
                    params.rows
                , List.find
                    (\key ->
                        AudienceItem.getIdString key.item == error.colId
                    )
                    params.cols
                )
            of
                -- We do the same for errors
                ( Just row, Just col ) ->
                    Just
                        { row = row
                        , col = col
                        , cellData =
                            AvAData
                                { data =
                                    Tracked.Failure
                                        (XB2.Share.Gwi.Http.CustomError params.trackerId
                                            (xbQueryErrorStringWithoutCodeTranslation error.error)
                                            error.error
                                        )
                                , incompatibilities = Tracked.NotAsked
                                }
                        }

                ( Nothing, Nothing ) ->
                    Nothing

                ( Just _, Nothing ) ->
                    Nothing

                ( Nothing, Just _ ) ->
                    Nothing


{-| Helper function inside the bulk API response logic to prepare for crosstab total cell
insertion. Meant to be used alongside a `List.filterMap` for the Maybe values.

It differs from the above function in that this doesn't care about both the row and col
being both audience items found in the crosstab, but only one of them or none. Items
returned from the response that are not found in the crosstab are the total ones, which
come represented with an id of `"0"`.

-}
bulkIntersectionResponseToMaybeTotalInfoWithData :
    { rows : List ACrosstab.Key
    , cols : List ACrosstab.Key
    , trackerId : Tracked.TrackerId
    }
    -> AudienceIntersect.BulkIntersectionResponse
    ->
        Maybe
            { row : AudienceItem
            , col : AudienceItem
            , itemWhichIsNotTotals : AudienceItem
            , cellData : CellData
            }
bulkIntersectionResponseToMaybeTotalInfoWithData params response =
    case response of
        AudienceIntersect.BulkIntersectionSuccess data ->
            case
                ( List.find
                    (\key ->
                        AudienceItem.getIdString key.item == data.audiences.row.id
                    )
                    params.rows
                , List.find
                    (\key ->
                        AudienceItem.getIdString key.item == data.audiences.col.id
                    )
                    params.cols
                )
            of
                -- If both items are not totals then we don't care about the response.
                ( Just _, Just _ ) ->
                    Nothing

                -- Otherwise since `Nothing` represents the total item we set `row` or `col` to the total item if that's the case.
                ( Nothing, Nothing ) ->
                    Just
                        { row = AudienceItem.totalItem
                        , col = AudienceItem.totalItem
                        , itemWhichIsNotTotals = AudienceItem.totalItem
                        , cellData =
                            AvAData
                                { data =
                                    Tracked.Success
                                        { intersection =
                                            { size = data.intersection.size
                                            , sample = data.intersection.sample
                                            , index = data.intersection.index
                                            }
                                        , audiences =
                                            { row =
                                                { id = data.audiences.row.id
                                                , intersectPercentage =
                                                    data.audiences.row.intersectPercentage
                                                , sample = data.audiences.row.sample
                                                , size = data.audiences.row.size
                                                }
                                            , col =
                                                { id = data.audiences.col.id
                                                , intersectPercentage =
                                                    data.audiences.col.intersectPercentage
                                                , sample = data.audiences.col.sample
                                                , size = data.audiences.col.size
                                                }
                                            }
                                        , stretching = Nothing
                                        }
                                , incompatibilities = Tracked.NotAsked
                                }
                        }

                ( Just row, Nothing ) ->
                    Just
                        { row = row.item
                        , col = AudienceItem.totalItem
                        , itemWhichIsNotTotals = row.item
                        , cellData =
                            AvAData
                                { data =
                                    Tracked.Success
                                        { intersection =
                                            { size = data.intersection.size
                                            , sample = data.intersection.sample
                                            , index = data.intersection.index
                                            }
                                        , audiences =
                                            { row =
                                                { id = data.audiences.row.id
                                                , intersectPercentage =
                                                    data.audiences.row.intersectPercentage
                                                , sample = data.audiences.row.sample
                                                , size = data.audiences.row.size
                                                }
                                            , col =
                                                { id = data.audiences.col.id
                                                , intersectPercentage =
                                                    data.audiences.col.intersectPercentage
                                                , sample = data.audiences.col.sample
                                                , size = data.audiences.col.size
                                                }
                                            }
                                        , stretching = Nothing
                                        }
                                , incompatibilities = Tracked.NotAsked
                                }
                        }

                ( Nothing, Just col ) ->
                    Just
                        { row = AudienceItem.totalItem
                        , col = col.item
                        , itemWhichIsNotTotals = col.item
                        , cellData =
                            AvAData
                                { data =
                                    Tracked.Success
                                        { intersection =
                                            { size = data.intersection.size
                                            , sample = data.intersection.sample
                                            , index = data.intersection.index
                                            }
                                        , audiences =
                                            { row =
                                                { id = data.audiences.row.id
                                                , intersectPercentage =
                                                    data.audiences.row.intersectPercentage
                                                , sample = data.audiences.row.sample
                                                , size = data.audiences.row.size
                                                }
                                            , col =
                                                { id = data.audiences.col.id
                                                , intersectPercentage =
                                                    data.audiences.col.intersectPercentage
                                                , sample = data.audiences.col.sample
                                                , size = data.audiences.col.size
                                                }
                                            }
                                        , stretching = Nothing
                                        }
                                , incompatibilities = Tracked.NotAsked
                                }
                        }

        AudienceIntersect.BulkQueryError error ->
            case
                ( List.find
                    (\key ->
                        AudienceItem.getIdString key.item == error.rowId
                    )
                    params.rows
                , List.find
                    (\key ->
                        AudienceItem.getIdString key.item == error.colId
                    )
                    params.cols
                )
            of
                -- Works the same way for errors
                ( Just _, Just _ ) ->
                    Nothing

                ( Just row, Nothing ) ->
                    Just
                        { row = row.item
                        , col = AudienceItem.totalItem
                        , itemWhichIsNotTotals = row.item
                        , cellData =
                            AvAData
                                { data =
                                    Tracked.Failure
                                        (XB2.Share.Gwi.Http.CustomError params.trackerId
                                            (xbQueryErrorStringWithoutCodeTranslation error.error)
                                            error.error
                                        )
                                , incompatibilities = Tracked.NotAsked
                                }
                        }

                ( Nothing, Just col ) ->
                    Just
                        { row = AudienceItem.totalItem
                        , col = col.item
                        , itemWhichIsNotTotals = col.item
                        , cellData =
                            AvAData
                                { data =
                                    Tracked.Failure
                                        (XB2.Share.Gwi.Http.CustomError params.trackerId
                                            (xbQueryErrorStringWithoutCodeTranslation error.error)
                                            error.error
                                        )
                                , incompatibilities = Tracked.NotAsked
                                }
                        }

                ( Nothing, Nothing ) ->
                    Just
                        { row = AudienceItem.totalItem
                        , col = AudienceItem.totalItem
                        , itemWhichIsNotTotals = AudienceItem.totalItem
                        , cellData =
                            AvAData
                                { data =
                                    Tracked.Failure
                                        (XB2.Share.Gwi.Http.CustomError params.trackerId
                                            (xbQueryErrorStringWithoutCodeTranslation error.error)
                                            error.error
                                        )
                                , incompatibilities = Tracked.NotAsked
                                }
                        }


type alias CrosstabBulkAvARequestData =
    { rows : List ACrosstab.Key
    , cols : List ACrosstab.Key
    , rowExprs : List Expression
    , colExprs : List Expression
    }


sendCrosstabBulkAvARequest :
    CrosstabBulkAvARequestData
    -> CrosstabCommandResolveArgs msg afterAction
    -> Cmd msg
sendCrosstabBulkAvARequest requestData resolveArgs =
    let
        -- We do not need to send the BaseAudience to the backend when it's the default one.
        maybeBaseAudience : Maybe BaseAudience
        maybeBaseAudience =
            if BaseAudience.isDefault resolveArgs.baseAudience then
                Nothing

            else
                Just resolveArgs.baseAudience

        audienceItemToQueryAudienceParam :
            ACrosstab.Key
            -> Expression.Expression
            ->
                { id : AudienceItemId.AudienceItemId
                , expression : Expression.Expression
                , key : ACrosstab.Key
                }
        audienceItemToQueryAudienceParam key audienceExpression =
            { id = AudienceItem.getId key.item
            , expression = audienceExpression
            , key = key
            }
    in
    sendBulkAvARequest
        { config = resolveArgs.config
        , trackedToMsg =
            \responseJsonSeq ->
                let
                    -- Total responses are excluded from here because they're not found inside the crosstabTable.cells.
                    crosstabTableKeysAndCellDatas :
                        List
                            { row : ACrosstab.Key
                            , col : ACrosstab.Key
                            , cellData : CellData
                            }
                    crosstabTableKeysAndCellDatas =
                        Tracked.map
                            (List.filterMap
                                (bulkIntersectionResponseToMaybeRowColData
                                    { rows = requestData.rows
                                    , cols = requestData.cols
                                    , trackerId = resolveArgs.trackerId
                                    }
                                )
                            )
                            responseJsonSeq
                            -- TODO: BEWARE! Bug-prone behaviour
                            |> Tracked.withDefault []

                    -- Total responses. We work with the placeholder "0" id we get from the response to identify them.
                    crosstabTotalItemsAndCellDatas :
                        List
                            { row : AudienceItem
                            , col : AudienceItem
                            , itemWhichIsNotTotals : AudienceItem
                            , cellData : CellData
                            }
                    crosstabTotalItemsAndCellDatas =
                        Tracked.map
                            (List.filterMap
                                (bulkIntersectionResponseToMaybeTotalInfoWithData
                                    { rows = requestData.rows
                                    , cols = requestData.cols
                                    , trackerId = resolveArgs.trackerId
                                    }
                                )
                            )
                            responseJsonSeq
                            -- TODO: BEWARE! Bug-prone behaviour
                            |> Tracked.withDefault []
                in
                BulkCellsLoaded
                    resolveArgs.requestOrigin
                    resolveArgs.activeLocations
                    resolveArgs.activeWaves
                    resolveArgs.baseAudience
                    crosstabTableKeysAndCellDatas
                    crosstabTotalItemsAndCellDatas
        }
        { rows =
            List.map2 audienceItemToQueryAudienceParam
                requestData.rows
                requestData.rowExprs
        , cols =
            List.map2 audienceItemToQueryAudienceParam
                requestData.cols
                requestData.colExprs
        , locations = resolveArgs.activeLocations
        , waves = resolveArgs.activeWaves
        , maybeBaseAudience = maybeBaseAudience
        , requestOrigin = resolveArgs.requestOrigin
        , flags = resolveArgs.flags
        , trackerId = resolveArgs.trackerId
        }


type alias AvARequestData =
    { row : AudienceParam
    , col : AudienceParam
    , trackedToMsg : Tracked.WebData XBQueryError IntersectResult -> Msg
    }


sendAvARequest :
    AvARequestData
    -> RequestOrigin
    -> Config msg afterAction
    -> Flags
    -> Tracked.TrackerId
    -> IdSet WaveCodeTag
    -> IdSet LocationCodeTag
    -> BaseAudience
    -> Cmd msg
sendAvARequest ({ trackedToMsg } as data) requestOrigin config flags trackerId activeWaves activeLocations baseAudience =
    let
        requestBaseAudience =
            if BaseAudience.isDefault baseAudience then
                Nothing

            else
                Just baseAudience

        toTrackedMsg : Result (Error XBQueryError) IntersectResult -> msg
        toTrackedMsg result =
            result
                |> Tracked.fromResult
                |> trackedToMsg
                |> config.msg
    in
    AudienceIntersect.request
        flags
        requestOrigin
        requestBaseAudience
        (Set.Any.toList activeLocations)
        (Set.Any.toList activeWaves)
        trackerId
        { row = data.row
        , column = data.col
        }
        |> Cmd.map (handleCellLoadResponse config toTrackedMsg)


type alias AverageRequestData =
    { average : Average
    , unit : QuestionAveragesUnit

    -- Nothing used so we can encode "audience: null" in Average vs Total requests
    , audience : Maybe Expression
    , trackedToMsg : Tracked.WebData XBQueryError AverageResult -> Msg
    }


sendAverageRequest :
    AverageRequestData
    -> Config msg afterAction
    -> Flags
    -> Question
    -> BaseAudience
    -> IdSet LocationCodeTag
    -> IdSet WaveCodeTag
    -> Tracked.TrackerId
    -> Cmd msg
sendAverageRequest { average, unit, audience, trackedToMsg } config flags question baseAudience activeLocations activeWaves trackerId =
    let
        requestBaseAudience =
            if BaseAudience.isDefault baseAudience then
                Nothing

            else
                Just baseAudience

        toTrackedMsg =
            Tracked.fromResult
                >> trackedToMsg
                >> config.msg
    in
    Average.request
        flags
        question
        requestBaseAudience
        (Set.Any.toList activeLocations)
        (Set.Any.toList activeWaves)
        trackerId
        average
        audience
        unit
        |> Cmd.map (handleCellLoadResponse config toTrackedMsg)


type alias CrosstabCommandResolveArgs msg afterAction =
    { config : Config msg afterAction
    , flags : Flags
    , trackerId : Tracked.TrackerId
    , activeWaves : IdSet WaveCodeTag
    , activeLocations : IdSet LocationCodeTag
    , baseAudience : BaseAudience
    , requestOrigin : RequestOrigin
    }


sendTotalVsTotalRequest : CrosstabCommandResolveArgs msg afterAction -> Cmd msg
sendTotalVsTotalRequest { requestOrigin, config, flags, trackerId, activeWaves, activeLocations, baseAudience } =
    sendAvARequest
        { row = AudienceIntersect.Total
        , col = AudienceIntersect.Total
        , trackedToMsg =
            ACrosstab.initAvACellData
                >> TotalsCellLoaded
                    requestOrigin
                    activeLocations
                    activeWaves
                    { row = AudienceItem.totalItem, col = AudienceItem.totalItem }
                    { item = AudienceItem.totalItem
                    , base = baseAudience
                    }
        }
        requestOrigin
        config
        flags
        trackerId
        activeWaves
        activeLocations
        baseAudience


sendIncompatibilitiesBulkRequest :
    { rows : List ACrosstab.Key
    , cols : List ACrosstab.Key
    , rowExprs : List Expression
    , colExprs : List Expression
    }
    -> CrosstabCommandResolveArgs msg afterAction
    -> Cmd msg
sendIncompatibilitiesBulkRequest params resolveArgs =
    let
        rowItems =
            List.map .item params.rows

        colItems =
            List.map .item params.cols

        handleIncompatibilitiesResponse :
            Result (Error Never) XBApi.GetIncompatibilitiesBulkResponse
            -> msg
        handleIncompatibilitiesResponse result =
            result
                |> Tracked.fromResult
                |> (\responseJson ->
                        case responseJson of
                            Tracked.Success successResponse ->
                                let
                                    incompatibilitiesPerCell =
                                        successResponse.cellsResponse
                                            |> AssocSet.toList
                                            |> List.filterMap
                                                (\cellResponse ->
                                                    case
                                                        ( List.find
                                                            (\{ item } ->
                                                                AudienceItem.getId item == cellResponse.rowId
                                                            )
                                                            params.rows
                                                        , List.find
                                                            (\{ item } ->
                                                                AudienceItem.getId item == cellResponse.columnId
                                                            )
                                                            params.cols
                                                        )
                                                    of
                                                        ( Just row, Just col ) ->
                                                            Just
                                                                { row = row
                                                                , col = col
                                                                , base = resolveArgs.baseAudience
                                                                , incompatibilities =
                                                                    AssocSet.toList cellResponse.attributes
                                                                        {- We have to filter out the incompatibilities that are skipped
                                                                           due to "waves"/"locations" exceptions.
                                                                           (See: https://globalwebindex.atlassian.net/browse/AUR-1007)
                                                                        -}
                                                                        |> List.filter (\attribute -> Maybe.unwrap True not (Nullish.toMaybe attribute.questionExceptionsSkip))
                                                                        |> List.fastConcatMap
                                                                            (\attribute ->
                                                                                AssocSet.toList attribute.incompatibilities
                                                                            )
                                                                        |> List.foldl
                                                                            (\incompatibility incompatibilitiesAcc ->
                                                                                Dict.Any.insert incompatibility.locationCode
                                                                                    { locationCode = incompatibility.locationCode
                                                                                    , waveCodes =
                                                                                        Set.Any.fromList XB2.Share.Data.Id.unwrap
                                                                                            (AssocSet.toList incompatibility.waveCodes)
                                                                                    }
                                                                                    incompatibilitiesAcc
                                                                            )
                                                                            XB2.Share.Data.Id.emptyDict
                                                                        |> Tracked.Success
                                                                }

                                                        _ ->
                                                            Nothing
                                                )

                                    incompatibilityTotals =
                                        successResponse.cellsResponse
                                            |> AssocSet.toList
                                            |> List.filterMap
                                                (\cellResponse ->
                                                    case
                                                        ( List.find
                                                            (\{ item } ->
                                                                AudienceItem.getId item == cellResponse.rowId
                                                            )
                                                            params.rows
                                                        , List.find
                                                            (\{ item } ->
                                                                AudienceItem.getId item == cellResponse.columnId
                                                            )
                                                            params.cols
                                                        )
                                                    of
                                                        ( Just _, Just _ ) ->
                                                            Nothing

                                                        ( Just row, Nothing ) ->
                                                            Just
                                                                { item = row.item
                                                                , base = resolveArgs.baseAudience
                                                                , incompatibilities =
                                                                    AssocSet.toList cellResponse.attributes
                                                                        {- We have to filter out the incompatibilities that are skipped
                                                                           due to "waves"/"locations" exceptions.
                                                                           (See: https://globalwebindex.atlassian.net/browse/AUR-1007)
                                                                        -}
                                                                        |> List.filter (\attribute -> Maybe.unwrap True not (Nullish.toMaybe attribute.questionExceptionsSkip))
                                                                        |> List.fastConcatMap
                                                                            (\attribute ->
                                                                                AssocSet.toList attribute.incompatibilities
                                                                            )
                                                                        |> List.foldl
                                                                            (\incompatibility incompatibilitiesAcc ->
                                                                                Dict.Any.insert incompatibility.locationCode
                                                                                    { locationCode = incompatibility.locationCode
                                                                                    , waveCodes =
                                                                                        Set.Any.fromList XB2.Share.Data.Id.unwrap
                                                                                            (AssocSet.toList incompatibility.waveCodes)
                                                                                    }
                                                                                    incompatibilitiesAcc
                                                                            )
                                                                            XB2.Share.Data.Id.emptyDict
                                                                        |> Tracked.Success
                                                                }

                                                        ( Nothing, Just col ) ->
                                                            Just
                                                                { item = col.item
                                                                , base = resolveArgs.baseAudience
                                                                , incompatibilities =
                                                                    AssocSet.toList cellResponse.attributes
                                                                        {- We have to filter out the incompatibilities that are skipped
                                                                           due to "waves"/"locations" exceptions.
                                                                           (See: https://globalwebindex.atlassian.net/browse/AUR-1007)
                                                                        -}
                                                                        |> List.filter (\attribute -> Maybe.unwrap True not (Nullish.toMaybe attribute.questionExceptionsSkip))
                                                                        |> List.fastConcatMap
                                                                            (\attribute ->
                                                                                AssocSet.toList attribute.incompatibilities
                                                                            )
                                                                        |> List.foldl
                                                                            (\incompatibility incompatibilitiesAcc ->
                                                                                Dict.Any.insert incompatibility.locationCode
                                                                                    { locationCode = incompatibility.locationCode
                                                                                    , waveCodes =
                                                                                        Set.Any.fromList XB2.Share.Data.Id.unwrap
                                                                                            (AssocSet.toList incompatibility.waveCodes)
                                                                                    }
                                                                                    incompatibilitiesAcc
                                                                            )
                                                                            XB2.Share.Data.Id.emptyDict
                                                                        |> Tracked.Success
                                                                }

                                                        ( Nothing, Nothing ) ->
                                                            -- TotalvsTotal incompatibilities are not supported.
                                                            Nothing
                                                )
                                in
                                BulkCellIncompatibilitiesLoaded
                                    resolveArgs.activeLocations
                                    resolveArgs.activeWaves
                                    incompatibilitiesPerCell
                                    incompatibilityTotals
                                    |> resolveArgs.config.msg

                            Tracked.Failure _ ->
                                let
                                    incompatibilitiesPerCell =
                                        cartesianProductOfKeys
                                            |> List.filterMap
                                                (\( row, col ) ->
                                                    Maybe.map2
                                                        (\rowKey colKey ->
                                                            { row = rowKey
                                                            , col = colKey
                                                            , base = resolveArgs.baseAudience

                                                            -- Fallback for failure response. We're just setting empty
                                                            , incompatibilities = Tracked.Success XB2.Share.Data.Id.emptyDict
                                                            }
                                                        )
                                                        row
                                                        col
                                                )

                                    incompatibilityTotals =
                                        cartesianProductOfKeys
                                            |> List.filterMap
                                                (\( row, col ) ->
                                                    case ( row, col ) of
                                                        ( Just _, Just _ ) ->
                                                            Nothing

                                                        ( Just rowKey, Nothing ) ->
                                                            Just
                                                                { item = rowKey.item
                                                                , base = resolveArgs.baseAudience

                                                                -- Fallback for failure response. We're just setting empty
                                                                , incompatibilities = Tracked.Success XB2.Share.Data.Id.emptyDict
                                                                }

                                                        ( Nothing, Just colKey ) ->
                                                            Just
                                                                { item = colKey.item
                                                                , base = resolveArgs.baseAudience

                                                                -- Fallback for failure response. We're just setting empty
                                                                , incompatibilities = Tracked.Success XB2.Share.Data.Id.emptyDict
                                                                }

                                                        ( Nothing, Nothing ) ->
                                                            -- TotalvsTotal incompatibilities are not supported.
                                                            Nothing
                                                )
                                in
                                -- Fallback for failure response. We're just setting empty
                                -- incompatibilities for failed cells. Maybe a warning in
                                -- the future indicating we couldn't load the
                                -- incompatibilities for this case?
                                -- TODO: Handle decoding issues in a proper way for error messages.
                                BulkCellIncompatibilitiesLoaded
                                    resolveArgs.activeLocations
                                    resolveArgs.activeWaves
                                    incompatibilitiesPerCell
                                    incompatibilityTotals
                                    |> resolveArgs.config.msg

                            Tracked.Loading _ ->
                                resolveArgs.config.msg NoOp

                            Tracked.NotAsked ->
                                -- TODO: Something here is needed? Do we even reach this?
                                resolveArgs.config.msg NoOp
                   )

        cartesian : List a -> List b -> List ( a, b )
        cartesian xs ys =
            List.fastConcatMap
                (\x -> List.map (\y -> ( x, y )) ys)
                xs

        cartesianProductOfCells =
            cartesian (List.map2 Tuple.pair (Nothing :: List.map Just rowItems) (Nothing :: List.map Just params.rowExprs))
                (List.map2 Tuple.pair (Nothing :: List.map Just colItems) (Nothing :: List.map Just params.colExprs))
                |> List.filterNot (\( ( row, _ ), ( col, _ ) ) -> row == Nothing && col == Nothing)

        cartesianProductOfKeys =
            cartesian (Nothing :: List.map Just params.rows)
                (Nothing :: List.map Just params.cols)
                |> List.filterNot (\( row, col ) -> row == Nothing && col == Nothing)

        cells : AssocSet.Set XBApi.Cell
        cells =
            cartesianProductOfCells
                |> List.map
                    (\( ( rowItem, rowExpr ), ( colItem, colExpr ) ) ->
                        { rowId = Maybe.map AudienceItem.getId rowItem
                        , columnId = Maybe.map AudienceItem.getId colItem
                        , attributes =
                            (Maybe.map getP2AttributesFromExpression rowExpr
                                |> Maybe.withDefault []
                            )
                                ++ (Maybe.map getP2AttributesFromExpression colExpr
                                        |> Maybe.withDefault []
                                   )
                                |> AssocSet.fromList
                        }
                    )
                |> AssocSet.fromList

        getP2AttributesFromExpression =
            Expression.foldr
                (\leaf acc ->
                    let
                        ( namespace, qCode ) =
                            XB2.Share.Data.Labels.splitQuestionCode leaf.namespaceAndQuestionCode

                        maybeFirstSuffixCode : Maybe Suffix.Code
                        maybeFirstSuffixCode =
                            Optional.map NonemptyList.head leaf.suffixCodes
                                |> Optional.toMaybe
                    in
                    List.map
                        (\dtpCode ->
                            let
                                -- TODO: Handle this in a proper way
                                datapointCode =
                                    {- Fix for the waves question code, datapoint for
                                       "waves" questions has the question code as a prefix
                                       for some reason. E.g. "waves" & "q1_2024"
                                       datapoint (Q1 of 2024).
                                    -}
                                    if XB2.Share.Data.Id.unwrap qCode == "waves" then
                                        XB2.Share.Data.Id.fromString (XB2.Share.Data.Id.unwrap dtpCode)

                                    else
                                        Tuple.second <|
                                            XB2.Share.Data.Labels.splitQuestionAndDatapointCode dtpCode
                            in
                            { questionCode = qCode
                            , datapointCode = datapointCode
                            , maybeSuffixCode = maybeFirstSuffixCode
                            , namespaceCode = namespace
                            }
                        )
                        (NonemptyList.toList leaf.questionAndDatapointCodes)
                        ++ acc
                )
                []
    in
    XBApi.postIncompatibilitiesBulk
        { flags = resolveArgs.flags
        , trackerId = resolveArgs.trackerId
        , request =
            { cells = cells
            , filters =
                { locationCodes =
                    AssocSet.fromList (Set.Any.toList resolveArgs.activeLocations)
                , waveCodes = AssocSet.fromList (Set.Any.toList resolveArgs.activeWaves)
                }
            }
        }
        |> Cmd.map handleIncompatibilitiesResponse


type AverageRequestStatus msg
    = GetQuestionAndFetchLater (Cmd msg)
    | ExecuteThisCmd (Cmd msg)
    | FetchLater


resolveAverageRequest :
    Config msg afterAction
    -> Average
    -> (QuestionAveragesUnit -> data)
    -> XB2.Share.Store.Platform2.Store
    -> (data -> RemoteData (Error err) a -> Msg)
    -> (Question -> data -> Cmd msg)
    -> AverageRequestStatus msg
resolveAverageRequest config average getData p2Store failCmd createCmd =
    let
        questionCode =
            Average.getQuestionCode average
    in
    case XB2.Share.Store.Platform2.getQuestion questionCode p2Store of
        RemoteData.NotAsked ->
            GetQuestionAndFetchLater <|
                Cmd.perform
                    (config.fetchManyP2
                        [ XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = True } questionCode ]
                    )

        RemoteData.Loading ->
            FetchLater

        RemoteData.Failure _ ->
            getData (OtherUnit "ERROR")
                |> (\data ->
                        Task.succeed (Failure (OtherError QuestionForAverageNotAvailable))
                            |> Task.perform
                                (config.msg << failCmd data)
                   )
                |> ExecuteThisCmd

        RemoteData.Success question ->
            (case question.averagesUnit of
                Just unit ->
                    createCmd question <| getData unit

                Nothing ->
                    Cmd.none
            )
                |> ExecuteThisCmd


sendAverageRowRequest : XB2.Share.Store.Platform2.Store -> AverageRowRequestData -> CrosstabCommandResolveArgs msg afterAction -> AverageRequestStatus msg
sendAverageRowRequest p2Store data_ { config, flags, trackerId, activeWaves, activeLocations, baseAudience, requestOrigin } =
    resolveAverageRequest config
        data_.average
        data_.getData
        p2Store
        (\{ row, col } ->
            ACrosstab.AverageData
                >> CellLoaded
                    requestOrigin
                    activeLocations
                    activeWaves
                    { row = row
                    , col = col
                    , base = baseAudience
                    }
        )
        (\question data ->
            sendAverageRequest
                { average = data.rowAverage
                , unit = data.rowUnit
                , audience = Just data.colExpr
                , trackedToMsg =
                    ACrosstab.AverageData
                        >> CellLoaded
                            requestOrigin
                            activeLocations
                            activeWaves
                            { row = data.row
                            , col = data.col
                            , base = baseAudience
                            }
                }
                config
                flags
                question
                baseAudience
                activeLocations
                activeWaves
                trackerId
        )


sendAverageColRequest : XB2.Share.Store.Platform2.Store -> AverageColRequestData -> CrosstabCommandResolveArgs msg afterAction -> AverageRequestStatus msg
sendAverageColRequest p2Store data_ { config, flags, trackerId, activeWaves, activeLocations, baseAudience, requestOrigin } =
    resolveAverageRequest config
        data_.average
        data_.getData
        p2Store
        (\{ row, col } ->
            ACrosstab.AverageData
                >> CellLoaded
                    requestOrigin
                    activeLocations
                    activeWaves
                    { row = row
                    , col = col
                    , base = baseAudience
                    }
        )
        (\question data ->
            sendAverageRequest
                { average = data.colAverage
                , unit = data.colUnit
                , audience = Just data.rowExpr
                , trackedToMsg =
                    ACrosstab.AverageData
                        >> CellLoaded
                            requestOrigin
                            activeLocations
                            activeWaves
                            { row = data.row
                            , col = data.col
                            , base = baseAudience
                            }
                }
                config
                flags
                question
                baseAudience
                activeLocations
                activeWaves
                trackerId
        )


sendTotalRowAverageColRequest : XB2.Share.Store.Platform2.Store -> TotalRowAverageColRequestData -> CrosstabCommandResolveArgs msg afterAction -> AverageRequestStatus msg
sendTotalRowAverageColRequest p2Store data { config, flags, trackerId, activeWaves, activeLocations, baseAudience, requestOrigin } =
    resolveAverageRequest config
        data.average
        data.getData
        p2Store
        (\{ col } ->
            ACrosstab.AverageData
                >> TotalsCellLoaded
                    requestOrigin
                    activeLocations
                    activeWaves
                    { row = AudienceItem.totalItem, col = col }
                    { item = col
                    , base = baseAudience
                    }
        )
        (\question { col, colAverage, colUnit } ->
            sendAverageRequest
                { average = colAverage
                , unit = colUnit
                , audience = Nothing
                , trackedToMsg =
                    ACrosstab.AverageData
                        >> TotalsCellLoaded
                            requestOrigin
                            activeLocations
                            activeWaves
                            { row = AudienceItem.totalItem, col = col }
                            { item = col
                            , base = baseAudience
                            }
                }
                config
                flags
                question
                baseAudience
                activeLocations
                activeWaves
                trackerId
        )


sendTotalColAverageRowRequest : XB2.Share.Store.Platform2.Store -> TotalColAverageRowRequestData -> CrosstabCommandResolveArgs msg afterAction -> AverageRequestStatus msg
sendTotalColAverageRowRequest p2Store data { config, flags, trackerId, activeWaves, activeLocations, baseAudience, requestOrigin } =
    resolveAverageRequest config
        data.average
        data.getData
        p2Store
        (\{ row } ->
            ACrosstab.AverageData
                >> TotalsCellLoaded
                    requestOrigin
                    activeLocations
                    activeWaves
                    { row = row, col = AudienceItem.totalItem }
                    { item = row
                    , base = baseAudience
                    }
        )
        (\question { row, rowAverage, rowUnit } ->
            sendAverageRequest
                { average = rowAverage
                , unit = rowUnit
                , audience = Nothing
                , trackedToMsg =
                    ACrosstab.AverageData
                        >> TotalsCellLoaded
                            requestOrigin
                            activeLocations
                            activeWaves
                            { row = row, col = AudienceItem.totalItem }
                            { item = row
                            , base = baseAudience
                            }
                }
                config
                flags
                question
                baseAudience
                activeLocations
                activeWaves
                trackerId
        )


interpretCrosstabCommand : Config msg afterAction -> Flags -> XB2.Share.Store.Platform2.Store -> ACrosstab.Command -> Model afterAction -> ( Model afterAction, Cmd msg )
interpretCrosstabCommand config flags p2Store command model =
    case command of
        ACrosstab.CancelHttpRequest trackerId ->
            model
                |> Cmd.with (Http.cancel trackerId)

        ACrosstab.MakeHttpRequest trackerId activeWaves activeLocations baseAudience params ->
            let
                resolveCmd cmd =
                    Cmd.with cmd model

                enqueueCommand () =
                    { model | crosstabCommandsQueue = Queue.enqueue command model.crosstabCommandsQueue }

                resolveAverage : AverageRequestStatus msg -> ( Model afterAction, Cmd msg )
                resolveAverage status =
                    case status of
                        ExecuteThisCmd cmd ->
                            resolveCmd cmd

                        FetchLater ->
                            enqueueCommand ()
                                |> Cmd.pure

                        GetQuestionAndFetchLater cmd ->
                            enqueueCommand ()
                                |> Cmd.with cmd

                sendRequest =
                    case params of
                        TotalVsTotalRequest ->
                            sendTotalVsTotalRequest >> resolveCmd

                        AverageRowRequest r ->
                            sendAverageRowRequest p2Store r >> resolveAverage

                        AverageColRequest r ->
                            sendAverageColRequest p2Store r >> resolveAverage

                        TotalRowAverageColRequest r ->
                            sendTotalRowAverageColRequest p2Store r >> resolveAverage

                        TotalColAverageRowRequest r ->
                            sendTotalColAverageRowRequest p2Store r >> resolveAverage

                        AverageVsAverageRequest r ->
                            \_ ->
                                Task.succeed (Failure (OtherError XBAvgVsAvgNotSupported))
                                    |> Task.perform
                                        (config.msg
                                            << CellLoaded
                                                model.requestOrigin
                                                activeLocations
                                                activeWaves
                                                { row = r.row
                                                , col = r.col
                                                , base = baseAudience
                                                }
                                            << ACrosstab.AverageData
                                        )
                                    |> resolveCmd

                        CrosstabBulkAvARequest r ->
                            sendCrosstabBulkAvARequest
                                { rows = r.rows
                                , cols = r.cols
                                , rowExprs = r.rowExprs
                                , colExprs = r.colExprs
                                }
                                >> resolveCmd

                        IncompatibilityBulkRequest r ->
                            sendIncompatibilitiesBulkRequest
                                { rows = r.rows
                                , cols = r.cols
                                , rowExprs = r.rowExprs
                                , colExprs = r.colExprs
                                }
                                >> resolveCmd
            in
            sendRequest
                { config = config
                , flags = flags
                , trackerId = trackerId
                , activeWaves = activeWaves
                , activeLocations = activeLocations
                , baseAudience = baseAudience
                , requestOrigin = model.requestOrigin
                }


interpretCrosstabCommands : Config msg afterAction -> Flags -> XB2.Share.Store.Platform2.Store -> List ACrosstab.Command -> Model afterAction -> ( Model afterAction, Cmd msg )
interpretCrosstabCommands config flags p2Store commands model =
    List.foldl
        (\command ( m, cmds ) ->
            let
                ( newModel, cmd ) =
                    interpretCrosstabCommand config flags p2Store command m
            in
            ( newModel, cmd :: cmds )
        )
        ( model, [] )
        commands
        |> Tuple.mapSecond Cmd.batch


interpretCommands : Config msg afterAction -> Flags -> XB2.Share.Store.Platform2.Store -> RequestOrigin -> List ACrosstab.Command -> Model afterAction -> ( Model afterAction, Cmd msg )
interpretCommands config flags p2Store requestOrigin commands model =
    interpretCrosstabCommands config flags p2Store commands { model | requestOrigin = requestOrigin }


cancelAllLoadingRequests : Config msg afterAction -> Flags -> XB2.Share.Store.Platform2.Store -> Model afterAction -> ( Model afterAction, Cmd msg )
cancelAllLoadingRequests config flags p2Store model =
    let
        ( newCrosstab, commands ) =
            ACrosstab.cancelAllLoadingRequests <| currentCrosstab model
    in
    { model
        | crosstabCommandsQueue = Queue.empty
        , afterQueueFinishedCmd = NoCmd
        , openedCellLoaderModal = NoCellLoaderModal
        , audienceCrosstab = newCrosstab
    }
        |> interpretCrosstabCommands config flags p2Store commands


reloadNotAskedCellsIfFullLoadRequested : Config msg afterAction -> Flags -> XB2.Share.Store.Platform2.Store -> Model afterAction -> ( Model afterAction, Cmd msg )
reloadNotAskedCellsIfFullLoadRequested config flags p2Store model =
    let
        crosstab =
            currentCrosstab model

        ( newCrosstab, reloadCellsCommands ) =
            ACrosstab.loadAllNotAskedCellsData crosstab
    in
    if ACrosstab.isFullyLoadedCellData crosstab then
        processAfterQueueCmd config model

    else
        let
            requestsLimit =
                maxRequestsLimit - ACrosstab.loadingCount crosstab
        in
        { model
            | crosstabCommandsQueue = List.foldl Queue.enqueue model.crosstabCommandsQueue <| List.drop requestsLimit reloadCellsCommands
            , openedCellLoaderModal = LoadWithoutProgress
            , audienceCrosstab = newCrosstab
        }
            |> interpretCrosstabCommands config flags p2Store (List.take requestsLimit reloadCellsCommands)


reloadNotAskedCellsIfFullLoadRequestedWithOriginAndMsg : Config msg afterAction -> afterAction -> RequestOrigin -> Model afterAction -> ( Model afterAction, Cmd msg )
reloadNotAskedCellsIfFullLoadRequestedWithOriginAndMsg config afterAction requestOrigin model =
    { model | requestOrigin = requestOrigin, afterQueueFinishedCmd = WaitingForTime afterAction }
        |> Cmd.with
            (Time.now
                |> Task.perform (SetStartTimeAndReaload >> config.msg)
            )


setShouldBeLoadedForSorting : SortConfig -> AudienceCrosstab -> AudienceCrosstab
setShouldBeLoadedForSorting { axis, mode } =
    let
        setShouldBeLoadedRowOrCol id =
            case axis of
                Rows ->
                    ACrosstab.setColumnShouldBeLoaded id

                Columns ->
                    ACrosstab.setRowShouldBeLoaded id
    in
    case mode of
        ByOtherAxisMetric id _ _ ->
            setShouldBeLoadedRowOrCol id

        ByOtherAxisAverage id _ ->
            setShouldBeLoadedRowOrCol id

        ByTotalsMetric _ _ ->
            case axis of
                Rows ->
                    ACrosstab.setLoadNotAskedTotalRows

                Columns ->
                    ACrosstab.setLoadNotAskedTotalColumns

        ByName _ ->
            identity

        NoSort ->
            identity


allNotDoneCellsForSorting : SortConfig -> AudienceCrosstab -> Int
allNotDoneCellsForSorting { axis, mode } crosstab =
    let
        notLoadedRowsOrCols id =
            case axis of
                Rows ->
                    ACrosstab.notDoneForColumnCount id crosstab

                Columns ->
                    ACrosstab.notDoneForRowCount id crosstab
    in
    case mode of
        ByOtherAxisMetric id _ _ ->
            notLoadedRowsOrCols id

        ByOtherAxisAverage id _ ->
            notLoadedRowsOrCols id

        ByTotalsMetric _ _ ->
            case axis of
                Rows ->
                    ACrosstab.totalsNotDoneForRowCount crosstab

                Columns ->
                    ACrosstab.totalsNotDoneForColumnCount crosstab

        ByName _ ->
            0

        NoSort ->
            0


reloadOnlyNeededCellsForSorting :
    Config msg afterAction
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> NonEmpty SortConfig
    -> Model afterAction
    -> ( Model afterAction, Cmd msg )
reloadOnlyNeededCellsForSorting config flags p2Store sortConfigs model =
    let
        crosstab =
            model.audienceCrosstab

        ( newCrosstab, reloadCellsCommands ) =
            sortConfigs
                |> NonemptyList.foldr
                    (\sortConfig ->
                        setShouldBeLoadedForSorting sortConfig
                    )
                    crosstab
                |> ACrosstab.reloadNotAskedCells

        currentlyNotLoadedCells : Int
        currentlyNotLoadedCells =
            sortConfigs
                |> NonemptyList.foldr
                    (\sortConfig ->
                        (+) <|
                            allNotDoneCellsForSorting sortConfig crosstab
                    )
                    0
    in
    if currentlyNotLoadedCells == 0 || List.isEmpty reloadCellsCommands then
        processAfterQueueCmd config model

    else
        let
            requestsLimit =
                maxRequestsLimit - ACrosstab.loadingCount crosstab
        in
        { model
            | openedCellLoaderModal = LoadWithoutProgress
            , crosstabCommandsQueue =
                List.foldl Queue.enqueue model.crosstabCommandsQueue <|
                    List.drop requestsLimit reloadCellsCommands
            , audienceCrosstab = newCrosstab
        }
            |> interpretCrosstabCommands config
                flags
                p2Store
                (List.take requestsLimit reloadCellsCommands)


reloadOnlyNeededCellsForSortingWithOriginAndMsg : Config msg afterAction -> afterAction -> RequestOrigin -> NonEmpty SortConfig -> Model afterAction -> ( Model afterAction, Cmd msg )
reloadOnlyNeededCellsForSortingWithOriginAndMsg config afterAction requestOrigin sortConfigs model =
    { model | requestOrigin = requestOrigin, afterQueueFinishedCmd = WaitingForTime afterAction }
        |> Cmd.with
            (Time.now
                |> Task.perform (SetStartTimeAndRealoadForSorting sortConfigs >> config.msg)
            )


showFullTableLoader : Model afterAction -> Bool
showFullTableLoader =
    .openedCellLoaderModal >> (/=) NoCellLoaderModal


resetRetries : Model afterAction -> ( Model afterAction, Cmd msg )
resetRetries model =
    Cmd.pure { model | retries = Dict.empty }


isFullyLoaded : Model afterAction -> Bool
isFullyLoaded { audienceCrosstab } =
    ACrosstab.isFullyLoadedCellData audienceCrosstab


notLoadedCellCount : Model afterAction -> Int
notLoadedCellCount { audienceCrosstab } =
    ACrosstab.notLoadedCellDataCount audienceCrosstab
