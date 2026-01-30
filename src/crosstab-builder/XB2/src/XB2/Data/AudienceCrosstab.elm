module XB2.Data.AudienceCrosstab exposing
    ( AffixGroupItem
    , AffixedItemCounts
    , AudienceCrosstab
    , AudienceInserter
    , AverageColRequestData
    , AverageRowRequestData
    , AverageVsAverageRequestData
    , AverageVsDbuRequestData
    , Cell
    , CellData(..)
    , CellDataResult
    , CellIndexes
    , Command(..)
    , CrosstabBaseAudience(..)
    , CrosstabBulkAvARequestData
    , CrosstabTable
    , DbuColRequestData
    , DbuRowRequestData
    , DbuVsAverageRequestData
    , DbuVsDbuRequestData
    , Direction(..)
    , EditGroupItem
    , EditedItemCounts
    , ErrorAddingBase
    , ErrorAddingRowOrColumn
    , HeatmapBehaviour(..)
    , Incompatibilities
    , Incompatibility
    , Key
    , MovableItems
    , MultipleAudiencesInserter
    , OriginalOrder(..)
    , RequestParams(..)
    , SelectableBaseItem
    , TotalColAverageRowRequestData
    , TotalColDbuRowRequestData
    , TotalRowAverageColRequestData
    , TotalRowDbuColRequestData
    , Totals
    , VisibleCells
    , addAudiences
    , addAudiencesOneByOne
    , addBases
    , addColumn
    , addColumns
    , addColumnsAtIndex
    , addRow
    , addRows
    , addRowsAtIndex
    , affixGroups
    , allBasesSelected
    , allColumnsSelected
    , allRowsSelected
    , anyBaseSelected
    , anySelected
    , basesNotEdided
    , cancelAllLoadingRequests
    , cancelUnfinishedRequests
    , clearBasesSelection
    , colCountWithoutTotals
    , computeKeyMapping
    , createNewBaseAudience
    , crosstabSizeLimit
    , deselectAll
    , deselectAllColumns
    , deselectAllRows
    , deselectColumn
    , deselectRow
    , editGroups
    , empty
    , emptyCell
    , emptyCrosstabTable
    , forceCellShouldBeLoaded
    , forceTotalCellShouldBeLoaded
    , generateBulkTrackerId
    , getActiveLocations
    , getActiveWaves
    , getAvAData
    , getAverageData
    , getBaseAudiences
    , getBaseAudiencesCount
    , getColumns
    , getCrosstab
    , getCrosstabBaseAudiences
    , getCurrentBaseAudience
    , getCurrentBaseAudienceIndex
    , getDeviceBasedUsageData
    , getDimensionsWithTotals
    , getFilteredMetricValue
    , getKeyMapping
    , getNonselectedColumns
    , getNonselectedRows
    , getRange
    , getRows
    , getSeed
    , getSelectedBases
    , getSelectedColumns
    , getSelectedRows
    , getSizeWithTotals
    , getSizeWithoutTotals
    , getTotals
    , getVisibleCells
    , getVisibleCellsForRender
    , goToBaseAtIndex
    , heatmapBehaviour
    , init
    , initAvACellData
    , initCell
    , initFromProject
    , insertCrosstabCell
    , insertIncompatibilities
    , insertTotalIncompatibilities
    , insertTotalsCell
    , isAnyNotAskedOrLoading
    , isBaseSelected
    , isCellDataFailure
    , isCellSuccess
    , isDefaultBase
    , isEmpty
    , isFullyLoaded
    , isFullyLoadedCellData
    , isLoading
    , isMovableItemsMember
    , keyNamespaceCodes
    , keyToComparable
    , loadAllNotAskedCellsData
    , loadedCellDataCount
    , loadingCount
    , mapOrder
    , moveItemsToColumnIndex
    , moveItemsToRowIndex
    , namespaceCodes
    , namespaceCodesWithBases
    , notDoneForColumnCount
    , notDoneForRowCount
    , notLoadedCellDataCount
    , notSame
    , questionCodes
    , questionCodesWithBases
    , reloadCell
    , reloadNotAskedCells
    , reloadNotLoadedCells
    , reloadTotalCell
    , removeAudiences
    , removeBase
    , removeBases
    , replaceBaseAudience
    , replaceDefaultBaseAudience
    , replaceItem
    , replaceKey
    , resetDefaultBaseAudience
    , rowCountWithoutTotals
    , selectAllBases
    , selectAllColumns
    , selectAllRows
    , selectColumn
    , selectColumnWithShift
    , selectRow
    , selectRowWithShift
    , selectableColCountWithoutTotals
    , selectableRowCountWithoutTotals
    , selectedBases
    , selectedBasesCount
    , setActiveLocations
    , setActiveWaves
    , setBaseAudienceAtIndexWithCommands
    , setBasesOrder
    , setCellsVisibility
    , setColumnShouldBeLoaded
    , setFocusToBase
    , setLoadNotAskedTotalColumns
    , setLoadNotAskedTotalRows
    , setRowShouldBeLoaded
    , switchRowsAndColumns
    , toggleBaseAudience
    , totalKeyToComparable
    , totalsNotDoneForColumnCount
    , totalsNotDoneForRowCount
    , unwrapCrosstabBase
    , updateCrosstab
    , value
    , valueForAudienceItem
    )

{-| This module builds on top of plain Crosstab (which is agnostic to what's stored in its cells)
and makes it specific to the business domain

  - We specialize the contents of each cell to be audience IntersectResult
  - We associate IntersectResult with each totals cell
  - We create / cancel HTTP requests for data loading into crosstab / totals cells

-}

import Basics.Extra exposing (flip)
import Dict
import Dict.Any exposing (AnyDict)
import List.Extra as List
import List.NonEmpty as NonemptyList exposing (NonEmpty)
import List.NonEmpty.Zipper as Zipper exposing (Zipper)
import Maybe.Extra as Maybe
import Random
import Set exposing (Set)
import Set.Any exposing (AnySet)
import Time exposing (Posix)
import XB2.Data exposing (AudienceDefinition(..), XBProjectFullyLoaded)
import XB2.Data.Audience.Expression exposing (Expression)
import XB2.Data.AudienceItem as AudienceItem exposing (AudienceItem)
import XB2.Data.AudienceItemId as AudienceItemId exposing (AudienceItemId)
import XB2.Data.Average exposing (Average(..))
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect
    exposing
        ( IntersectResult
        , XBQueryError
        )
import XB2.Data.Calc.Average exposing (AverageResult, DeviceBasedUsageResult)
import XB2.Data.Caption exposing (Caption)
import XB2.Data.Crosstab as Crosstab exposing (Crosstab)
import XB2.Data.DeviceBasedUsage as DeviceBasedUsage
import XB2.Data.Metric exposing (Metric(..))
import XB2.Data.Namespace as Namespace
import XB2.Data.Range as Range exposing (Range)
import XB2.RemoteData.Tracked as Tracked
import XB2.Share.Data.Id exposing (IdSet)
import XB2.Share.Data.Labels
    exposing
        ( Location
        , LocationCodeTag
        , NamespaceAndQuestionCode
        , QuestionAveragesUnit
        , Wave
        , WaveCodeTag
        )
import XB2.Share.Gwi.List as List
import XB2.Share.Permissions exposing (Can)
import XB2.Sort exposing (Sort)


{-| Direction where the `AudienceItem` is placed.

  - `Row` means ↓
  - `Column` means →

-}
type Direction
    = Row
    | Column


type alias MovableItems =
    NonEmpty ( Direction, Key )


isMovableItemsMember : Key -> MovableItems -> Bool
isMovableItemsMember key items =
    items
        |> NonemptyList.map Tuple.second
        |> NonemptyList.member key


type AudienceCrosstab
    = AudienceCrosstab
        { crosstab : CrosstabTable
        , totals : Totals
        , activeWaves : IdSet WaveCodeTag
        , activeLocations : IdSet LocationCodeTag
        , bases : Zipper CrosstabBaseAudience
        , visibleCells : VisibleCells

        {- This limit number stays the same over the lifetime of the crosstab
           (even with the addition and removal of bases): it gets divided by the
           number of the bases.

           The reason it's tracked here instead of being a constant is that some
           tests have a small limit (~10) to be able to test this functionality.
        -}
        , limit : Int

        {- Boundaries for cells out of visible area considered to be loaded.
           Example:
            loadingBoundaries = 1
            V - visible (will be loaded)
            L - loaded  (will be loaded)
            _________________
            | L | L | L |___|
            | L | V | L |___|
            | L | L | L |___|
            |___|___|___|___|
        -}
        , loadingBoundaries : Int
        , keyMapping : AnyDict AudienceItemId.ComparableId AudienceItemId Key
        , seed : Random.Seed
        }


type alias SelectableBaseItem =
    { base : BaseAudience
    , isSelected : Bool
    }


type CrosstabBaseAudience
    = DefaultBase BaseAudience
    | SelectableBase SelectableBaseItem


selectableBase : BaseAudience -> Bool -> CrosstabBaseAudience
selectableBase base selected =
    SelectableBase <| SelectableBaseItem base selected


type alias CellIndexes =
    { rowIndex : Int
    , columnIndex : Int
    }


type alias Key =
    { item : AudienceItem
    , {- Note Average rows/cols can't be selected. We don't enforce this in the
         type system yet...
      -}
      isSelected : Bool
    }


type alias CrosstabTable =
    Crosstab Key BaseAudience Cell


type alias ErrorAddingRowOrColumn =
    { exceedingSize : Int
    , sizeLimit : Int
    , currentBasesCount : Int
    }


type alias ErrorAddingBase =
    { currentBasesCount : Int
    , totalLimit : Int
    , maxBasesCount : Int
    , exceededBasesBy : Int
    }


{-| Information about which cells are currently visible in the table.
(Deals with indices, not with AudienceItemIds / Keys.)

Image table (whole visible)

         0   1   2   3   4
       +---+---+---+---+---+
     0 |   |   |   |   |   |
       +---+---+---+---+---+
     1 |   |   |   |   |   |
       +---+---+---+---+---+

Then we have indices (0,0) for top left and (4,1) for the bottom right cell
which means also:

    { topLeftRow = 0
    , topLeftCol = 0
    , bottomRightRow = 1
    , bottomRightCol = 4
    }

-}
type alias VisibleCells =
    { topLeftRow : Int
    , topLeftCol : Int
    , bottomRightRow : Int
    , bottomRightCol : Int

    -- The amount of Rows/Columns that have been frozen from 0 to x
    , frozenRows : Int
    , frozenCols : Int
    }


defaultVisibleCells : VisibleCells
defaultVisibleCells =
    VisibleCells -1 -1 -1 -1 -1 -1


type alias CellDataResult =
    Tracked.WebData XBQueryError IntersectResult


type alias Incompatibility =
    { location : Location
    , waves : List Wave
    }


type alias Incompatibilities =
    Tracked.WebData Never (List Incompatibility)


{-| there are two types of rows/cols:

  - audience expression
  - average question (potentially with datapoint for with suffixes)

and that translates directly to what the cells can contain:

  - audience expression vs audience expression = AvA query
  - audience expression vs average question = Average query

(we don't support average vs average)

-}
type CellData
    = AvAData { data : CellDataResult, incompatibilities : Incompatibilities }
    | AverageData (Tracked.WebData XBQueryError AverageResult)
    | DeviceBasedUsageData (Tracked.WebData XBQueryError DeviceBasedUsageResult)


mapIntersectResult : (IntersectResult -> IntersectResult) -> CellData -> CellData
mapIntersectResult fn cellData =
    case cellData of
        AvAData avaData ->
            { avaData | data = Tracked.map fn avaData.data }
                |> AvAData

        AverageData _ ->
            cellData

        DeviceBasedUsageData _ ->
            cellData


type alias Cell =
    { data : CellData
    , isVisible : Bool
    , shouldBeLoaded : Bool
    }


initAvACellData : CellDataResult -> CellData
initAvACellData cellDataResult =
    AvAData { data = cellDataResult, incompatibilities = Tracked.NotAsked }


initCell : CellDataResult -> Incompatibilities -> Cell
initCell data incompatibilities =
    { data = AvAData { data = data, incompatibilities = incompatibilities }
    , isVisible = False
    , shouldBeLoaded = False
    }


emptyCell : Cell
emptyCell =
    initCell Tracked.NotAsked Tracked.NotAsked


type alias Totals =
    AnyDict ( AudienceItemId.ComparableId, String ) ( AudienceItem, BaseAudience ) Cell


{-| Function to insert AudienceItem into crosstab
-}
type alias AudienceInserter =
    Key -> AudienceCrosstab -> Result ErrorAddingRowOrColumn AudienceCrosstab


{-| Function to insert multiple AudienceItems into crosstab at once
-}
type alias MultipleAudiencesInserter =
    List { value : CellData, key : Key } -> AudienceCrosstab -> Result ErrorAddingRowOrColumn AudienceCrosstab


empty : Posix -> Int -> Int -> AudienceCrosstab
empty =
    init
        XB2.Share.Data.Id.emptySet
        XB2.Share.Data.Id.emptySet


notSame : AudienceCrosstab -> AudienceCrosstab -> Bool
notSame (AudienceCrosstab c1) (AudienceCrosstab c2) =
    (c1.seed /= c2.seed)
        || (c1.visibleCells /= c2.visibleCells)
        || (c1.loadingBoundaries /= c2.loadingBoundaries)
        || (c1.activeWaves /= c2.activeWaves)
        || (c1.activeLocations /= c2.activeLocations)
        || (c1.totals /= c2.totals)
        || (c1.crosstab /= c2.crosstab)


initBase : CrosstabBaseAudience
initBase =
    DefaultBase BaseAudience.default


init : IdSet WaveCodeTag -> IdSet LocationCodeTag -> Posix -> Int -> Int -> AudienceCrosstab
init activeWaves activeLocations posix limit loadingBoundaries =
    AudienceCrosstab
        { crosstab = emptyCrosstabTable
        , totals = initTotals (NonemptyList.singleton BaseAudience.default)
        , activeWaves = activeWaves
        , activeLocations = activeLocations
        , bases = Zipper.singleton initBase
        , limit = limit
        , loadingBoundaries = loadingBoundaries
        , visibleCells = defaultVisibleCells
        , keyMapping = computeKeyMapping emptyCrosstabTable
        , seed = Random.initialSeed <| Time.posixToMillis posix
        }


totalVsTotalCell : BaseAudience -> ( ( AudienceItem, BaseAudience ), Cell )
totalVsTotalCell base =
    ( ( AudienceItem.totalItem, base )
    , emptyCell
    )


totalKeyToComparable : ( AudienceItem, BaseAudience ) -> ( AudienceItemId.ComparableId, String )
totalKeyToComparable ( item, base ) =
    let
        baseId =
            base
                |> BaseAudience.getId
                |> AudienceItemId.toString
    in
    ( audienceItemToComparable item, baseId )


initTotals : NonEmpty BaseAudience -> Totals
initTotals bases =
    bases
        |> NonemptyList.toList
        |> List.map totalVsTotalCell
        |> Dict.Any.fromList totalKeyToComparable


{-| If this changed, check also logic in valueForAudienceItem
-}
keyToComparable : Key -> String
keyToComparable { item } =
    audienceItemToComparable item


keyToNotAskedCellData : Key -> CellData
keyToNotAskedCellData key =
    case AudienceItem.getDefinition key.item of
        Average _ ->
            AverageData Tracked.NotAsked

        DeviceBasedUsage _ ->
            DeviceBasedUsageData Tracked.NotAsked

        Expression _ ->
            AvAData { data = Tracked.NotAsked, incompatibilities = Tracked.NotAsked }


audienceItemToComparable : AudienceItem -> String
audienceItemToComparable item =
    AudienceItemId.toComparable <| AudienceItem.getId item


emptyCrosstabTable : CrosstabTable
emptyCrosstabTable =
    Crosstab.empty
        keyToComparable
        baseToComparable


baseToComparable : BaseAudience -> String
baseToComparable baseAudience =
    baseAudience
        |> BaseAudience.getId
        |> AudienceItemId.toString


getCrosstab : AudienceCrosstab -> CrosstabTable
getCrosstab (AudienceCrosstab { crosstab }) =
    crosstab


getTotals : AudienceCrosstab -> Totals
getTotals (AudienceCrosstab { totals }) =
    totals


getActiveWaves : AudienceCrosstab -> IdSet WaveCodeTag
getActiveWaves (AudienceCrosstab { activeWaves }) =
    activeWaves


getActiveLocations : AudienceCrosstab -> IdSet LocationCodeTag
getActiveLocations (AudienceCrosstab { activeLocations }) =
    activeLocations


getCurrentBaseAudience : AudienceCrosstab -> BaseAudience
getCurrentBaseAudience (AudienceCrosstab { bases }) =
    unwrapCrosstabBase <| Zipper.current bases


getCurrentBaseAudienceIndex : AudienceCrosstab -> Int
getCurrentBaseAudienceIndex (AudienceCrosstab { bases }) =
    Zipper.listPrev bases |> List.length


getBaseAudiences : AudienceCrosstab -> Zipper BaseAudience
getBaseAudiences (AudienceCrosstab { bases }) =
    Zipper.map unwrapCrosstabBase bases


findBaseAudience : BaseAudience -> AudienceCrosstab -> Maybe ( Int, BaseAudience )
findBaseAudience base (AudienceCrosstab { bases }) =
    findIndexById base bases
        |> Maybe.andThen
            (\i ->
                Zipper.goToIndex i bases
                    |> Maybe.map (Tuple.pair i << unwrapCrosstabBase << Zipper.current)
            )


isDefaultBase : CrosstabBaseAudience -> Bool
isDefaultBase crosstabBase =
    case crosstabBase of
        DefaultBase _ ->
            True

        SelectableBase _ ->
            False


isBaseSelected : CrosstabBaseAudience -> Bool
isBaseSelected crosstabBase =
    case crosstabBase of
        DefaultBase _ ->
            False

        SelectableBase b ->
            b.isSelected


getSelectedBases : AudienceCrosstab -> Maybe (NonEmpty BaseAudience)
getSelectedBases (AudienceCrosstab { bases }) =
    bases
        |> Zipper.toList
        |> List.foldr
            (\base acc ->
                if isBaseSelected base then
                    unwrapCrosstabBase base
                        |> Maybe.unwrap NonemptyList.singleton
                            (flip NonemptyList.cons)
                            acc
                        |> Just

                else
                    acc
            )
            Nothing


getCrosstabBaseAudiences : AudienceCrosstab -> Zipper CrosstabBaseAudience
getCrosstabBaseAudiences (AudienceCrosstab { bases }) =
    bases


anyBaseSelected : AudienceCrosstab -> Bool
anyBaseSelected (AudienceCrosstab { bases }) =
    Zipper.toList bases
        |> List.any isBaseSelected


allBasesSelected : AudienceCrosstab -> Bool
allBasesSelected (AudienceCrosstab { bases }) =
    Zipper.toList bases
        |> List.all isBaseSelected


selectedBases : AudienceCrosstab -> List BaseAudience
selectedBases (AudienceCrosstab { bases }) =
    Zipper.toList bases
        |> List.filter isBaseSelected
        |> List.map unwrapCrosstabBase


selectedBasesCount : AudienceCrosstab -> Int
selectedBasesCount =
    List.length << selectedBases


areBasesIdEqual : BaseAudience -> BaseAudience -> Bool
areBasesIdEqual base1 base2 =
    BaseAudience.getId base1 == BaseAudience.getId base2


toggleBaseAudience : BaseAudience -> AudienceCrosstab -> AudienceCrosstab
toggleBaseAudience base (AudienceCrosstab r) =
    r.bases
        |> Zipper.map
            (\sBase ->
                case sBase of
                    DefaultBase _ ->
                        sBase

                    SelectableBase baseData ->
                        if areBasesIdEqual baseData.base base then
                            SelectableBase { baseData | isSelected = not baseData.isSelected }

                        else
                            sBase
            )
        |> (\newBases -> AudienceCrosstab { r | bases = newBases })


selectAllBases : AudienceCrosstab -> AudienceCrosstab
selectAllBases (AudienceCrosstab r) =
    AudienceCrosstab
        { r
            | bases =
                Zipper.map
                    (\sBase ->
                        case sBase of
                            DefaultBase _ ->
                                sBase

                            SelectableBase baseData ->
                                SelectableBase { baseData | isSelected = True }
                    )
                    r.bases
        }


clearBasesSelection : AudienceCrosstab -> AudienceCrosstab
clearBasesSelection (AudienceCrosstab r) =
    AudienceCrosstab
        { r
            | bases =
                Zipper.map
                    (\sBase ->
                        case sBase of
                            DefaultBase _ ->
                                sBase

                            SelectableBase baseData ->
                                SelectableBase { baseData | isSelected = False }
                    )
                    r.bases
        }


getCrosstabBaseAudienceId : CrosstabBaseAudience -> AudienceItemId
getCrosstabBaseAudienceId crosstabBaseAudience =
    case crosstabBaseAudience of
        DefaultBase base ->
            BaseAudience.getId base

        SelectableBase { base } ->
            BaseAudience.getId base


replaceDefaultBaseAudience :
    BaseAudience
    -> AudienceCrosstab
    -> Maybe ( AudienceCrosstab, List Command )
replaceDefaultBaseAudience newDefaultBase ((AudienceCrosstab r) as crosstab) =
    r.bases
        |> Zipper.toList
        |> List.indexedFoldl
            (\index base acc ->
                if isDefaultBase base then
                    Just ( index, getCrosstabBaseAudienceId base )

                else
                    acc
            )
            Nothing
        |> Maybe.andThen
            (\( index, id ) ->
                setBaseAudienceAtIndexWithCommands
                    index
                    (BaseAudience.setId newDefaultBase id)
                    crosstab
            )


resetDefaultBaseAudience : AudienceCrosstab -> Maybe ( AudienceCrosstab, List Command )
resetDefaultBaseAudience =
    replaceDefaultBaseAudience BaseAudience.default


removeBases : NonEmpty BaseAudience -> AudienceCrosstab -> AudienceCrosstab
removeBases bases crosstab =
    NonemptyList.foldl removeBase crosstab bases


getBaseAudiencesCount : AudienceCrosstab -> Int
getBaseAudiencesCount (AudienceCrosstab { bases }) =
    Zipper.length bases


getSeed : AudienceCrosstab -> Random.Seed
getSeed (AudienceCrosstab { seed }) =
    seed


{-| Return Nothing if activeWaves are identical to crosstab's activeWaves (so no change and wasteful reloading is needed)
-}
setActiveWaves : IdSet WaveCodeTag -> AudienceCrosstab -> Maybe ( AudienceCrosstab, List Command )
setActiveWaves activeWaves (AudienceCrosstab r) =
    if Set.Any.toSet activeWaves /= Set.Any.toSet r.activeWaves then
        Just <|
            reloadAllCells
                (AudienceCrosstab { r | activeWaves = activeWaves })

    else
        Nothing


{-| Return Nothing if activeLocations are identical to crosstab's activeLocations (so no change and wasteful reloading is needed)
-}
setActiveLocations : IdSet LocationCodeTag -> AudienceCrosstab -> Maybe ( AudienceCrosstab, List Command )
setActiveLocations activeLocations (AudienceCrosstab r) =
    if activeLocations /= r.activeLocations then
        Just <|
            reloadAllCells
                (AudienceCrosstab { r | activeLocations = activeLocations })

    else
        Nothing


{-| Sets a new bases order based on the `NonEmpty` indices passed (i.e. first item comes
first).
-}
setBasesOrder : NonEmpty CrosstabBaseAudience -> Int -> AudienceCrosstab -> AudienceCrosstab
setBasesOrder baseAudiences indexToBeActive (AudienceCrosstab crosstab) =
    let
        newBases =
            Zipper.fromNonEmpty
                (baseAudiences
                    |> NonemptyList.reverse
                    |> (\( baseAudience, rest ) ->
                            ( case baseAudience of
                                DefaultBase _ ->
                                    baseAudience

                                SelectableBase { base } ->
                                    DefaultBase base
                            , List.map
                                (\baseToConvert ->
                                    case baseToConvert of
                                        DefaultBase base ->
                                            SelectableBase
                                                { base = base
                                                , isSelected = False
                                                }

                                        SelectableBase _ ->
                                            baseToConvert
                                )
                                rest
                            )
                       )
                    |> NonemptyList.reverse
                )
    in
    AudienceCrosstab
        { crosstab
            | bases =
                newBases
                    |> Zipper.goToIndex indexToBeActive
                    |> Maybe.withDefault newBases
        }


addBases :
    Random.Seed
    -> NonEmpty BaseAudience
    -> AudienceCrosstab
    -> Result ErrorAddingBase ( AudienceCrosstab, List Command )
addBases seed newBases (AudienceCrosstab r) =
    let
        addNewBase : BaseAudience -> AudienceCrosstab -> Result ErrorAddingBase AudienceCrosstab
        addNewBase newBase ((AudienceCrosstab ac) as crosstab) =
            if canCreateNewBaseAudience crosstab then
                AudienceCrosstab
                    { ac
                        | bases = Zipper.consBefore (selectableBase newBase False) ac.bases
                        , totals = addTotals newBase r.crosstab ac.totals
                        , crosstab = Crosstab.addBase newBase emptyCell ac.crosstab
                    }
                    |> Ok

            else
                let
                    maxBasesCount =
                        getMaxBasesCount crosstab

                    currentBasesCount =
                        Zipper.length r.bases
                in
                Err
                    { currentBasesCount = Zipper.length r.bases
                    , totalLimit = r.limit
                    , maxBasesCount = getMaxBasesCount crosstab
                    , exceededBasesBy = currentBasesCount + NonemptyList.length newBases - maxBasesCount
                    }

        createOrUpdateBase : BaseAudience -> AudienceCrosstab -> Result ErrorAddingBase AudienceCrosstab
        createOrUpdateBase newBase ct =
            findBaseAudience newBase ct
                |> Maybe.andThen
                    (\( index, _ ) ->
                        setBaseAudienceAtIndex index newBase ct
                    )
                |> Maybe.map Ok
                |> Maybe.withDefault (addNewBase newBase ct)
    in
    newBases
        |> NonemptyList.foldr (\base -> Result.andThen (createOrUpdateBase base)) (AudienceCrosstab { r | seed = seed } |> Ok)
        |> Result.map
            (setCellsVisibility True r.visibleCells
                >> reloadNotLoadedCells
            )


{-| Return Nothing if baseAudience is identical to crosstab's baseAudience
(so no change and wasteful reloading is needed)

Because of multiple bases, this is a bit tricky. Ideally we'd like to remove all
mentions of old current base from Totals, Bases and Crosstab. But:

  - if the new base is already present in bases, we mustn't replace its values
    with NotAsked
  - if the old base is in bases more than once, its values will be needed even
    after this replacement, so we mustn't remove them

-}
setBaseAudienceAtIndex : Int -> BaseAudience -> AudienceCrosstab -> Maybe AudienceCrosstab
setBaseAudienceAtIndex index newBase (AudienceCrosstab r) =
    r.bases
        |> Zipper.updateAtIndex index
            (\crosstabBase ->
                case crosstabBase of
                    DefaultBase _ ->
                        DefaultBase newBase

                    SelectableBase sBase ->
                        SelectableBase { sBase | base = newBase }
            )
        |> Maybe.map
            (\newBases ->
                let
                    oldBase : BaseAudience
                    oldBase =
                        Zipper.current r.bases |> unwrapCrosstabBase

                    oldBasesList : List BaseAudience
                    oldBasesList =
                        basesToList r.bases

                    newBasesList : List BaseAudience
                    newBasesList =
                        basesToList newBases

                    shouldRemoveCurrentValues =
                        List.notMember oldBase newBasesList

                    shouldAddNotAskedValues =
                        List.notMember newBase oldBasesList
                in
                AudienceCrosstab
                    { r
                        | bases = newBases
                        , totals =
                            r.totals
                                |> (if shouldRemoveCurrentValues then
                                        removeTotals oldBase

                                    else
                                        identity
                                   )
                                |> (if shouldAddNotAskedValues then
                                        addTotals newBase r.crosstab

                                    else
                                        identity
                                   )
                        , crosstab =
                            r.crosstab
                                |> (if shouldRemoveCurrentValues then
                                        Crosstab.removeBase oldBase

                                    else
                                        identity
                                   )
                                |> (if shouldAddNotAskedValues then
                                        Crosstab.addBase newBase emptyCell

                                    else
                                        identity
                                   )
                    }
            )


setBaseAudienceAtIndexWithCommands : Int -> BaseAudience -> AudienceCrosstab -> Maybe ( AudienceCrosstab, List Command )
setBaseAudienceAtIndexWithCommands index newBase crosstab =
    setBaseAudienceAtIndex index newBase crosstab |> Maybe.map reloadNotLoadedCells


removeTotals : BaseAudience -> Totals -> Totals
removeTotals oldBase totals =
    Dict.Any.filter
        (\( _, base ) _ -> base /= oldBase)
        totals


{-| Replace new base audience instead of existing one with matching ID
-}
replaceBaseAudience : BaseAudience -> AudienceCrosstab -> Maybe ( AudienceCrosstab, List Command )
replaceBaseAudience newBase crosstab =
    findBaseAudience newBase crosstab
        |> Maybe.andThen
            (\( index, _ ) ->
                setBaseAudienceAtIndexWithCommands index newBase crosstab
            )


canCreateNewBaseAudience : AudienceCrosstab -> Bool
canCreateNewBaseAudience ((AudienceCrosstab { limit, bases }) as crosstab) =
    let
        newLimit =
            getLimitForBasesCount
                { limit = limit
                , basesCount = Zipper.length bases + 1
                }

        count =
            getSizeWithTotals crosstab
    in
    count <= newLimit


getMaxBasesCount : AudienceCrosstab -> Int
getMaxBasesCount ((AudienceCrosstab r) as crosstab) =
    r.limit // getSizeWithTotals crosstab


{-| Also moves to the newly created base.
-}
createNewBaseAudience : BaseAudience -> AudienceCrosstab -> Result ErrorAddingBase ( AudienceCrosstab, List Command )
createNewBaseAudience newBase ((AudienceCrosstab r) as crosstab) =
    if canCreateNewBaseAudience crosstab then
        let
            newBases =
                r.bases
                    |> Zipper.consBefore (selectableBase newBase False)

            oldBasesList =
                basesToList r.bases

            shouldAddNotAskedValues =
                List.notMember newBase oldBasesList
        in
        AudienceCrosstab
            { r
                | bases = newBases
                , totals =
                    r.totals
                        |> (if shouldAddNotAskedValues then
                                addTotals newBase r.crosstab

                            else
                                identity
                           )
                , crosstab =
                    r.crosstab
                        |> (if shouldAddNotAskedValues then
                                Crosstab.addBase newBase emptyCell

                            else
                                identity
                           )
            }
            |> setCellsVisibility True r.visibleCells
            |> reloadNotLoadedCells
            |> Ok

    else
        Err
            { currentBasesCount = Zipper.length r.bases
            , totalLimit = r.limit
            , maxBasesCount = getMaxBasesCount crosstab
            , exceededBasesBy = 1
            }


findIndexById : BaseAudience -> Zipper CrosstabBaseAudience -> Maybe Int
findIndexById baseAudience bases =
    bases
        |> Zipper.toList
        |> List.indexedFoldl
            (\index base acc ->
                if areBasesIdEqual baseAudience (unwrapCrosstabBase base) then
                    Just index

                else
                    acc
            )
            Nothing


removeBase : BaseAudience -> AudienceCrosstab -> AudienceCrosstab
removeBase base ((AudienceCrosstab r) as crosstab) =
    Zipper.focus (\b -> areBasesIdEqual base (unwrapCrosstabBase b)) r.bases
        |> Maybe.andThen
            (\basesWithIndexSelected ->
                let
                    maybeNewBases : Maybe (Zipper CrosstabBaseAudience)
                    maybeNewBases =
                        if not <| Zipper.hasNext basesWithIndexSelected then
                            basesWithIndexSelected
                                |> Zipper.dropl

                        else
                            basesWithIndexSelected
                                |> Zipper.dropr
                in
                maybeNewBases
                    |> Maybe.map
                        (\newBases ->
                            let
                                baseAtIndex : CrosstabBaseAudience
                                baseAtIndex =
                                    Zipper.current basesWithIndexSelected

                                newBasesList : List CrosstabBaseAudience
                                newBasesList =
                                    Zipper.toList newBases

                                shouldRemoveCurrentValues =
                                    List.notMember baseAtIndex newBasesList
                            in
                            AudienceCrosstab
                                { r
                                    | bases = newBases
                                    , totals =
                                        r.totals
                                            |> (if shouldRemoveCurrentValues then
                                                    removeTotals <| unwrapCrosstabBase baseAtIndex

                                                else
                                                    identity
                                               )
                                    , crosstab =
                                        r.crosstab
                                            |> (if shouldRemoveCurrentValues then
                                                    Crosstab.removeBase <| unwrapCrosstabBase baseAtIndex

                                                else
                                                    identity
                                               )
                                }
                        )
            )
        |> Maybe.withDefault crosstab


{-| Add new cells (NotAsked) to the Totals dict for the given base audience
-}
addTotals : BaseAudience -> CrosstabTable -> Totals -> Totals
addTotals base crosstab totals =
    let
        rowsAndCols =
            Set.Any.union
                (Set.Any.fromList keyToComparable <| Crosstab.getRows crosstab)
                (Set.Any.fromList keyToComparable <| Crosstab.getColumns crosstab)
                |> Set.Any.toList

        newTotals =
            rowsAndCols
                |> List.map (\{ item } -> ( item, base ))
                |> List.foldl
                    (\key acc -> Dict.Any.insert key emptyCell acc)
                    (Dict.Any.removeAll totals)

        totalVsTotal =
            Dict.Any.fromList
                totalKeyToComparable
                (List.singleton (totalVsTotalCell base))
    in
    Dict.Any.union newTotals totals
        |> Dict.Any.union totalVsTotal


getSizeWithoutTotals : AudienceCrosstab -> Int
getSizeWithoutTotals (AudienceCrosstab { crosstab }) =
    Crosstab.size crosstab


getSizeWithTotals : AudienceCrosstab -> Int
getSizeWithTotals (AudienceCrosstab { crosstab }) =
    (Crosstab.rowCount crosstab + 1) * (Crosstab.colCount crosstab + 1)


getDimensionsWithTotals : AudienceCrosstab -> { rowCount : Int, colCount : Int }
getDimensionsWithTotals (AudienceCrosstab { crosstab }) =
    { rowCount = Crosstab.rowCount crosstab + 1
    , colCount = Crosstab.colCount crosstab + 1
    }


{-| Add all audiences from the list using function which knows how to add single audience
-}
addAudiencesToCrosstab :
    AudienceInserter
    -> AudienceCrosstab
    -> List Key
    -> Result ErrorAddingRowOrColumn AudienceCrosstab
addAudiencesToCrosstab addAudienceToCrosstab crosstab =
    List.foldl (Result.andThen << addAudienceToCrosstab) (Ok crosstab)


replaceIdDuplicities : Set String -> ( List Key, Random.Seed ) -> ( List Key, Random.Seed )
replaceIdDuplicities idsInTable ( keys, seed ) =
    List.foldr
        (\key ( ( keyesAcc, seedSoFar ), ids ) ->
            let
                id =
                    AudienceItem.getIdString key.item
            in
            if Set.member id ids then
                let
                    ( itemWithNewId, newSeed ) =
                        AudienceItem.generateNewId key.item seedSoFar
                in
                ( ( { key | item = itemWithNewId } :: keyesAcc, newSeed ), Set.insert (AudienceItem.getIdString itemWithNewId) ids )

            else
                ( ( key :: keyesAcc, seedSoFar ), Set.insert id ids )
        )
        ( ( [], seed ), idsInTable )
        keys
        |> Tuple.first


addAudiencesPure :
    { fixIdDuplicities : Bool }
    -> MultipleAudiencesInserter
    -> List (Random.Seed -> ( Key, Random.Seed ))
    -> AudienceCrosstab
    -> Result ErrorAddingRowOrColumn AudienceCrosstab
addAudiencesPure { fixIdDuplicities } inserter audiences ((AudienceCrosstab r) as crosstab) =
    let
        ( keys, seed ) =
            List.foldr
                (\toKey ( items, currentSeed ) ->
                    toKey currentSeed
                        |> Tuple.mapFirst (\key -> key :: items)
                )
                ( [], r.seed )
                audiences
                |> (if fixIdDuplicities then
                        let
                            idsInTable =
                                (getColumns crosstab ++ getRows crosstab)
                                    |> List.map (.item >> AudienceItem.getIdString)
                                    |> Set.fromList
                        in
                        replaceIdDuplicities idsInTable

                    else
                        identity
                   )

        keysValues : List { key : Key, value : CellData }
        keysValues =
            List.map (\key -> { key = key, value = keyToNotAskedCellData key }) keys
    in
    inserter keysValues crosstab
        |> Result.map
            (\(AudienceCrosstab r_) ->
                AudienceCrosstab
                    { r_
                        | totals =
                            keys
                                |> addAudiencesToTotals
                                    (Zipper.toNonEmpty <| Zipper.map unwrapCrosstabBase r.bases)
                                    r.totals
                        , seed = seed
                    }
            )


addAudiencesOneByOnePure :
    { fixIdDuplicities : Bool }
    -> AudienceInserter
    -> List (Random.Seed -> ( Key, Random.Seed ))
    -> AudienceCrosstab
    -> Result ErrorAddingRowOrColumn AudienceCrosstab
addAudiencesOneByOnePure { fixIdDuplicities } addAudienceToCrosstab audiences ((AudienceCrosstab r) as crosstab) =
    let
        ( keys, seed ) =
            List.foldr
                (\toKey ( items, currentSeed ) ->
                    toKey currentSeed
                        |> Tuple.mapFirst (\key -> key :: items)
                )
                ( [], r.seed )
                audiences
                |> (if fixIdDuplicities then
                        let
                            idsInTable =
                                (getColumns crosstab ++ getRows crosstab)
                                    |> List.map (.item >> AudienceItem.getIdString)
                                    |> Set.fromList
                        in
                        replaceIdDuplicities idsInTable

                    else
                        identity
                   )
    in
    addAudiencesToCrosstab addAudienceToCrosstab crosstab keys
        |> Result.map
            (\(AudienceCrosstab r_) ->
                AudienceCrosstab
                    { r_
                        | totals =
                            keys
                                |> addAudiencesToTotals
                                    (Zipper.toNonEmpty <| Zipper.map unwrapCrosstabBase r.bases)
                                    r.totals
                        , seed = seed
                    }
            )


addAudiencesOneByOne :
    AudienceInserter
    -> List (Random.Seed -> ( Key, Random.Seed ))
    -> AudienceCrosstab
    -> Result ErrorAddingRowOrColumn ( AudienceCrosstab, List Command )
addAudiencesOneByOne addAudienceToCrosstab audiences ((AudienceCrosstab r) as crosstab) =
    addAudiencesOneByOnePure { fixIdDuplicities = False } addAudienceToCrosstab audiences crosstab
        |> Result.map
            (setCellsVisibility True r.visibleCells
                >> reloadNotLoadedCells
            )


addAudiences :
    MultipleAudiencesInserter
    -> List (Random.Seed -> ( Key, Random.Seed ))
    -> AudienceCrosstab
    -> Result ErrorAddingRowOrColumn ( AudienceCrosstab, List Command )
addAudiences inserter toKeys ((AudienceCrosstab ac) as crosstab) =
    let
        ( keys, seed ) =
            List.foldr
                (\toKey ( items, currentSeed ) ->
                    toKey currentSeed
                        |> Tuple.mapFirst (\key -> key :: items)
                )
                ( [], ac.seed )
                toKeys

        keysValues : List { key : Key, value : CellData }
        keysValues =
            List.map (\key -> { key = key, value = keyToNotAskedCellData key }) keys

        crosstabWithNewAudiences : Result ErrorAddingRowOrColumn AudienceCrosstab
        crosstabWithNewAudiences =
            inserter keysValues crosstab
                |> Result.map
                    (\(AudienceCrosstab r_) ->
                        AudienceCrosstab
                            { r_
                                | totals =
                                    keys
                                        |> addAudiencesToTotals
                                            (Zipper.toNonEmpty <| Zipper.map unwrapCrosstabBase ac.bases)
                                            ac.totals
                                , seed = seed
                            }
                    )
    in
    crosstabWithNewAudiences
        |> Result.map
            (setCellsVisibility True ac.visibleCells
                >> reloadNotLoadedCells
            )


addAudiencesToTotals : NonEmpty BaseAudience -> Totals -> List Key -> Totals
addAudiencesToTotals bases totals keys =
    keys
        |> List.fastConcatMap (\key -> List.map (Tuple.pair key) (NonemptyList.toList bases))
        |> List.foldl
            (\( key, base ) -> Dict.Any.insert ( key.item, base ) { emptyCell | data = keyToNotAskedCellData key })
            totals


{-| Data necessary for construction of `Cmd`s, the advantage compared to direct generation of commands would be testability.
-}
type Command
    = CancelHttpRequest Tracked.TrackerId
    | MakeHttpRequest Tracked.TrackerId (IdSet WaveCodeTag) (IdSet LocationCodeTag) BaseAudience RequestParams


type alias CrosstabBulkAvARequestData =
    { rows : List Key
    , cols : List Key
    , rowExprs : List Expression
    , colExprs : List Expression
    }


type alias AverageRowRequestData =
    { average : Average
    , getData :
        QuestionAveragesUnit
        ->
            { row : Key
            , col : Key
            , rowAverage : Average
            , rowUnit : QuestionAveragesUnit
            , colExpr : Expression
            }
    }


type alias DbuRowRequestData =
    { average : Average
    , getData :
        QuestionAveragesUnit
        ->
            { row : Key
            , col : Key
            , rowAverage : Average
            , rowUnit : QuestionAveragesUnit
            , colExpr : Expression
            }
    }


type alias AverageColRequestData =
    { average : Average
    , getData :
        QuestionAveragesUnit
        ->
            { row : Key
            , col : Key
            , rowExpr : Expression
            , colAverage : Average
            , colUnit : QuestionAveragesUnit
            }
    }


type alias DbuColRequestData =
    { average : Average
    , getData :
        QuestionAveragesUnit
        ->
            { row : Key
            , col : Key
            , rowExpr : Expression
            , colAverage : Average
            , colUnit : QuestionAveragesUnit
            }
    }


type alias TotalRowAverageColRequestData =
    { average : Average
    , getData :
        QuestionAveragesUnit
        ->
            { col : AudienceItem
            , colAverage : Average
            , colUnit : QuestionAveragesUnit
            }
    }


type alias TotalRowDbuColRequestData =
    { average : Average
    , getData :
        QuestionAveragesUnit
        ->
            { col : AudienceItem
            , colAverage : Average
            , colUnit : QuestionAveragesUnit
            }
    }


type alias TotalColAverageRowRequestData =
    { average : Average
    , getData :
        QuestionAveragesUnit
        ->
            { row : AudienceItem
            , rowAverage : Average
            , rowUnit : QuestionAveragesUnit
            }
    }


type alias TotalColDbuRowRequestData =
    { average : Average
    , getData :
        QuestionAveragesUnit
        ->
            { row : AudienceItem
            , rowAverage : Average
            , rowUnit : QuestionAveragesUnit
            }
    }


type alias AverageVsAverageRequestData =
    { row : Key
    , col : Key
    }


type alias DbuVsAverageRequestData =
    { row : Key
    , col : Key
    }


type alias DbuVsDbuRequestData =
    { row : Key
    , col : Key
    }


type alias AverageVsDbuRequestData =
    { row : Key
    , col : Key
    }


{-| TODO think of a better way to express
{Total,Expression,Average} x {Total,Expression,Average} than listing the
combinatorial explosion of all possible combinations.
-}
type RequestParams
    = TotalVsTotalRequest -- This is AvA too
      -- Bulk:
    | CrosstabBulkAvARequest CrosstabBulkAvARequestData
      -- Average:
    | AverageRowRequest AverageRowRequestData
    | DbuRowRequest DbuRowRequestData
    | AverageColRequest AverageColRequestData
    | DbuColRequest DbuColRequestData
    | TotalRowAverageColRequest TotalRowAverageColRequestData
    | TotalRowDbuColRequest TotalRowDbuColRequestData
    | TotalColAverageRowRequest TotalColAverageRowRequestData
    | TotalColDbuRowRequest TotalColDbuRowRequestData
    | {- unsupported: will be always N/A -} AverageVsAverageRequest AverageVsAverageRequestData
    | {- unsupported: will be always N/A -} AverageVsDbuRequest AverageVsDbuRequestData
    | {- unsupported: will be always N/A -} DbuVsDbuRequest DbuVsDbuRequestData
    | {- unsupported: will be always N/A -} DbuVsAverageRequest DbuVsAverageRequestData
    | IncompatibilityBulkRequest CrosstabBulkAvARequestData


cancelAllLoadingRequests : AudienceCrosstab -> ( AudienceCrosstab, List Command )
cancelAllLoadingRequests (AudienceCrosstab r) =
    let
        cancelTotalRequests =
            Dict.Any.foldl (\_ -> maybeAddCancelRequestCommand) [] r.totals

        cancelRequests =
            Crosstab.foldr (\_ -> maybeAddCancelRequestCommand) [] r.crosstab
    in
    ( AudienceCrosstab
        { r
            | crosstab = setCrosstabLoadingCellsAsNotLoaded r.crosstab
            , totals = setTotalsLoadingCellsAsNotLoaded r.totals
        }
    , cancelTotalRequests ++ cancelRequests
    )


reloadAllCells : AudienceCrosstab -> ( AudienceCrosstab, List Command )
reloadAllCells =
    reloadCells
        reloadCrosstabCellsWhichCanBeLoaded


reloadNotLoadedCells : AudienceCrosstab -> ( AudienceCrosstab, List Command )
reloadNotLoadedCells =
    reloadCells
        reloadNotLoadedCrosstabCellsWhichCanBeLoaded


combineMethodsReloadTotal : ( AudienceItem, BaseAudience ) -> AudienceCrosstab -> ( AudienceCrosstab, List Command )
combineMethodsReloadTotal key audience =
    let
        --ATC-6098 when you moves from another axis, yo have to reload the totals
        ( reloadedCrosstab1, commands1 ) =
            audience
                |> forceTotalCellShouldBeLoaded key
                |> reloadTotalCell key

        ( reloadedCrosstab2, commands2 ) =
            reloadNotLoadedCells reloadedCrosstab1
    in
    ( reloadedCrosstab2, commands1 ++ commands2 )


reloadNotAskedCells : AudienceCrosstab -> ( AudienceCrosstab, List Command )
reloadNotAskedCells =
    reloadCells
        reloadNotAskedCrosstabCellsWhichCanBeLoaded


reloadCell :
    { row : Key
    , col : Key
    , base : BaseAudience
    }
    -> AudienceCrosstab
    -> ( AudienceCrosstab, List Command )
reloadCell key =
    reloadCells
        (reloadCrosstabCellsBulk
            { clearAndCancelNotReloaded = False
            , shouldReloadCell = \key_ _ -> key == key_
            , shouldReloadIncompatibilities = \key_ _ -> key == key_
            }
            { clearAndCancelNotReloaded = False
            , shouldReloadCell = \_ _ -> False
            , shouldReloadIncompatibilities = \_ _ -> False
            }
        )


reloadTotalCell :
    ( AudienceItem, BaseAudience )
    -> AudienceCrosstab
    -> ( AudienceCrosstab, List Command )
reloadTotalCell key =
    reloadCells
        (reloadCrosstabCellsBulk
            { clearAndCancelNotReloaded = False
            , shouldReloadCell = \_ _ -> False
            , shouldReloadIncompatibilities = \_ _ -> False
            }
            { clearAndCancelNotReloaded = False
            , shouldReloadCell = \key_ _ -> key == key_
            , shouldReloadIncompatibilities = \key_ _ -> key == key_
            }
        )


loadAllNotAskedCellsData : AudienceCrosstab -> ( AudienceCrosstab, List Command )
loadAllNotAskedCellsData =
    reloadCells
        (reloadCrosstabCellsBulk
            { clearAndCancelNotReloaded = False
            , shouldReloadCell = \_ -> isCellDataNotAsked
            , shouldReloadIncompatibilities = \_ _ -> False
            }
            { clearAndCancelNotReloaded = False
            , shouldReloadCell = \_ -> isCellDataNotAsked
            , shouldReloadIncompatibilities = \_ _ -> False
            }
        )


reloadCells :
    (AudienceCrosstab -> ( AudienceCrosstab, List Command ))
    -> AudienceCrosstab
    -> ( AudienceCrosstab, List Command )
reloadCells crosstabCellReloader audienceCrosstab =
    crosstabCellReloader
        audienceCrosstab


reloadCrosstabCellsWhichCanBeLoaded : AudienceCrosstab -> ( AudienceCrosstab, List Command )
reloadCrosstabCellsWhichCanBeLoaded =
    reloadCrosstabCellsBulk
        { clearAndCancelNotReloaded = True
        , shouldReloadCell = \_ -> .shouldBeLoaded
        , shouldReloadIncompatibilities = \_ -> .shouldBeLoaded
        }
        { clearAndCancelNotReloaded = True
        , shouldReloadCell = \_ -> .shouldBeLoaded
        , shouldReloadIncompatibilities = \_ -> .shouldBeLoaded
        }


reloadNotLoadedCrosstabCellsWhichCanBeLoaded : AudienceCrosstab -> ( AudienceCrosstab, List Command )
reloadNotLoadedCrosstabCellsWhichCanBeLoaded =
    reloadCrosstabCellsBulk
        { clearAndCancelNotReloaded = False
        , shouldReloadCell = \_ c -> c.shouldBeLoaded && (not <| isCellDataDone c)
        , shouldReloadIncompatibilities = \_ c -> c.shouldBeLoaded && (not <| isIncompatibilitiesDone c)
        }
        { clearAndCancelNotReloaded = False
        , shouldReloadCell = \_ c -> c.shouldBeLoaded && (not <| isCellDataDone c)
        , shouldReloadIncompatibilities = \_ c -> c.shouldBeLoaded && (not <| isIncompatibilitiesDone c)
        }


reloadNotAskedCrosstabCellsWhichCanBeLoaded : AudienceCrosstab -> ( AudienceCrosstab, List Command )
reloadNotAskedCrosstabCellsWhichCanBeLoaded =
    reloadCrosstabCellsBulk
        { clearAndCancelNotReloaded = False
        , shouldReloadCell = \_ c -> c.shouldBeLoaded && isCellDataNotAsked c
        , shouldReloadIncompatibilities = \_ c -> c.shouldBeLoaded && isIncompatibilityNotAsked c
        }
        { clearAndCancelNotReloaded = False
        , shouldReloadCell = \_ c -> c.shouldBeLoaded && isCellDataNotAsked c
        , shouldReloadIncompatibilities = \_ c -> c.shouldBeLoaded && isIncompatibilityNotAsked c
        }


{-| TODO: Reduce cognitive complexity of this monstrosity.
TODO: Improve performance of this function.
-}
reloadCrosstabCellsBulk :
    { clearAndCancelNotReloaded : Bool
    , shouldReloadCell : { row : Key, col : Key, base : BaseAudience } -> Cell -> Bool
    , shouldReloadIncompatibilities :
        { row : Key, col : Key, base : BaseAudience }
        -> Cell
        -> Bool
    }
    ->
        { clearAndCancelNotReloaded : Bool
        , shouldReloadCell : ( AudienceItem, BaseAudience ) -> Cell -> Bool
        , shouldReloadIncompatibilities : ( AudienceItem, BaseAudience ) -> Cell -> Bool
        }
    -> AudienceCrosstab
    -> ( AudienceCrosstab, List Command )
reloadCrosstabCellsBulk crosstabTableLoadingConfig crosstabTotalsLoadingConfig (AudienceCrosstab audienceCrosstab) =
    let
        -- The active BaseAudience tab
        currentBaseAudience : BaseAudience
        currentBaseAudience =
            getCurrentBaseAudience (AudienceCrosstab audienceCrosstab)

        allTheRows : List Key
        allTheRows =
            Crosstab.getRows audienceCrosstab.crosstab
                |> List.filterNot (.item >> AudienceItem.isAverageOrDbu)

        allTheCols : List Key
        allTheCols =
            Crosstab.getColumns audienceCrosstab.crosstab
                |> List.filterNot (.item >> AudienceItem.isAverageOrDbu)

        rowItemIdSet : Set String
        rowItemIdSet =
            audienceCrosstab.crosstab
                |> Crosstab.getRows
                |> List.map (AudienceItem.getIdString << .item)
                |> Set.fromList

        colItemIdSet : Set String
        colItemIdSet =
            audienceCrosstab.crosstab
                |> Crosstab.getColumns
                |> List.map (AudienceItem.getIdString << .item)
                |> Set.fromList

        -- Hashed TrackerId used in the request
        bulkRequestTrackerId : Tracked.TrackerId
        bulkRequestTrackerId =
            generateBulkTrackerId audienceCrosstab.activeWaves
                audienceCrosstab.activeLocations
                currentBaseAudience
                audienceCrosstab.visibleCells

        -- Updated Tracked.Loading cells that are being fetched in the request & commands that this will fire
        -- For /intersection & /average responses
        -- TODO: Extract this into a helper function, and check logic
        ( newCrosstabTable, newCrosstabTableCmds, ( tableItemsWithRequest, tableIncompatibilitiesWithRequest ) ) =
            Crosstab.foldr
                (\key cell ( crosstabTableAcc, crosstabTableCmdsAcc, ( tableItemsWithRequestAcc, tableIncompatibilitiesWithRequestAcc ) ) ->
                    let
                        -- We check if the cell needs to be reloaded based on the passed config
                        -- E.g. we changed BaseAudience tab
                        willReloadThisCell : Bool
                        willReloadThisCell =
                            crosstabTableLoadingConfig.shouldReloadCell key cell

                        -- We check if the cell needs to be reloaded based on the passed config
                        -- E.g. we changed BaseAudience tab
                        willReloadIncompatibilities : Bool
                        willReloadIncompatibilities =
                            crosstabTableLoadingConfig.shouldReloadIncompatibilities key cell

                        -- We check if there are proper filters before populating the cell
                        hasLocationsAndWaves : Bool
                        hasLocationsAndWaves =
                            (not <| Set.Any.isEmpty audienceCrosstab.activeWaves)
                                && (not <| Set.Any.isEmpty audienceCrosstab.activeLocations)

                        {- We form the BulkRequest command above this context in the uppermost let .. in block.
                           Since both Incompatibilities & Average requests do not work in a bulk manner, we need to gather the commands
                           from the cells one by one.
                        -}
                        additionalCommandsToAdd : List Command
                        additionalCommandsToAdd =
                            let
                                trackerIdForCurrentItem : Tracked.TrackerId
                                trackerIdForCurrentItem =
                                    generateTrackerId
                                        audienceCrosstab.activeWaves
                                        audienceCrosstab.activeLocations
                                        key.base
                                        key.row.item
                                        key.col.item
                            in
                            case
                                ( AudienceItem.getDefinition key.row.item
                                , AudienceItem.getDefinition key.col.item
                                )
                            of
                                ( Expression _, Expression _ ) ->
                                    []

                                ( Expression rowExpr, Average colAverage ) ->
                                    if willReloadThisCell then
                                        [ MakeHttpRequest trackerIdForCurrentItem
                                            audienceCrosstab.activeWaves
                                            audienceCrosstab.activeLocations
                                            key.base
                                            (AverageColRequest
                                                { average = colAverage
                                                , getData =
                                                    \unit ->
                                                        { row = key.row
                                                        , col = key.col
                                                        , rowExpr = rowExpr
                                                        , colAverage = colAverage
                                                        , colUnit = unit
                                                        }
                                                }
                                            )
                                        ]

                                    else
                                        []

                                ( Expression rowExpr, DeviceBasedUsage colDbu ) ->
                                    if willReloadThisCell then
                                        [ MakeHttpRequest trackerIdForCurrentItem
                                            audienceCrosstab.activeWaves
                                            audienceCrosstab.activeLocations
                                            key.base
                                            (DbuColRequest
                                                { average = AvgWithoutSuffixes (DeviceBasedUsage.getQuestionCode colDbu)
                                                , getData =
                                                    \unit ->
                                                        { row = key.row
                                                        , col = key.col
                                                        , rowExpr = rowExpr
                                                        , colAverage = AvgWithoutSuffixes (DeviceBasedUsage.getQuestionCode colDbu)
                                                        , colUnit = unit
                                                        }
                                                }
                                            )
                                        ]

                                    else
                                        []

                                ( Average rowAverage, Expression colExpr ) ->
                                    if willReloadThisCell then
                                        [ MakeHttpRequest trackerIdForCurrentItem
                                            audienceCrosstab.activeWaves
                                            audienceCrosstab.activeLocations
                                            key.base
                                            (AverageRowRequest
                                                { average = rowAverage
                                                , getData =
                                                    \unit ->
                                                        { row = key.row
                                                        , col = key.col
                                                        , rowAverage = rowAverage
                                                        , rowUnit = unit
                                                        , colExpr = colExpr
                                                        }
                                                }
                                            )
                                        ]

                                    else
                                        []

                                ( DeviceBasedUsage rowDbu, Expression colExpr ) ->
                                    if willReloadThisCell then
                                        [ MakeHttpRequest trackerIdForCurrentItem
                                            audienceCrosstab.activeWaves
                                            audienceCrosstab.activeLocations
                                            key.base
                                            (DbuRowRequest
                                                { average = AvgWithoutSuffixes (DeviceBasedUsage.getQuestionCode rowDbu)
                                                , getData =
                                                    \unit ->
                                                        { row = key.row
                                                        , col = key.col
                                                        , rowAverage = AvgWithoutSuffixes (DeviceBasedUsage.getQuestionCode rowDbu)
                                                        , rowUnit = unit
                                                        , colExpr = colExpr
                                                        }
                                                }
                                            )
                                        ]

                                    else
                                        []

                                ( Average _, Average _ ) ->
                                    if willReloadThisCell then
                                        [ MakeHttpRequest trackerIdForCurrentItem
                                            audienceCrosstab.activeWaves
                                            audienceCrosstab.activeLocations
                                            key.base
                                            (AverageVsAverageRequest
                                                { row = key.row
                                                , col = key.col
                                                }
                                            )
                                        ]

                                    else
                                        []

                                ( DeviceBasedUsage _, DeviceBasedUsage _ ) ->
                                    if willReloadThisCell then
                                        [ MakeHttpRequest trackerIdForCurrentItem
                                            audienceCrosstab.activeWaves
                                            audienceCrosstab.activeLocations
                                            key.base
                                            (DbuVsDbuRequest
                                                { row = key.row
                                                , col = key.col
                                                }
                                            )
                                        ]

                                    else
                                        []

                                ( Average _, DeviceBasedUsage _ ) ->
                                    if willReloadThisCell then
                                        [ MakeHttpRequest trackerIdForCurrentItem
                                            audienceCrosstab.activeWaves
                                            audienceCrosstab.activeLocations
                                            key.base
                                            (AverageVsDbuRequest
                                                { row = key.row
                                                , col = key.col
                                                }
                                            )
                                        ]

                                    else
                                        []

                                ( DeviceBasedUsage _, Average _ ) ->
                                    if willReloadThisCell then
                                        [ MakeHttpRequest trackerIdForCurrentItem
                                            audienceCrosstab.activeWaves
                                            audienceCrosstab.activeLocations
                                            key.base
                                            (DbuVsAverageRequest
                                                { row = key.row
                                                , col = key.col
                                                }
                                            )
                                        ]

                                    else
                                        []
                    in
                    if hasLocationsAndWaves && (willReloadThisCell || willReloadIncompatibilities) then
                        ( Crosstab.insert key
                            { cell
                                | data =
                                    let
                                        trackerIdForCurrentItem : Tracked.TrackerId
                                        trackerIdForCurrentItem =
                                            generateTrackerId
                                                audienceCrosstab.activeWaves
                                                audienceCrosstab.activeLocations
                                                key.base
                                                key.row.item
                                                key.col.item
                                    in
                                    case cell.data of
                                        AvAData cellData ->
                                            -- Set the cell and incompatibilities as loading in case they need it (otherwise we ignore them and just go on)
                                            AvAData
                                                { cellData
                                                    | data =
                                                        if willReloadThisCell then
                                                            Tracked.loading bulkRequestTrackerId

                                                        else
                                                            cellData.data
                                                    , incompatibilities =
                                                        if willReloadIncompatibilities then
                                                            Tracked.loading
                                                                (bulkRequestTrackerId
                                                                    ++ "--incompatibilities"
                                                                )

                                                        else
                                                            cellData.incompatibilities
                                                }

                                        AverageData _ ->
                                            AverageData <|
                                                Tracked.loading trackerIdForCurrentItem

                                        DeviceBasedUsageData _ ->
                                            DeviceBasedUsageData <|
                                                Tracked.loading trackerIdForCurrentItem
                            }
                            crosstabTableAcc
                        , crosstabTableCmdsAcc ++ additionalCommandsToAdd
                        , ( if willReloadThisCell then
                                let
                                    {- We form an structure with the required cells to load like this:
                                       Grab the current base audience -> If the cell needs to be loaded then we push it into
                                       the Set for that baseAudience key:

                                       {"base-audience-1-id" = {rows = []
                                       , cols = ["col-audience-item-id-1"]}}
                                    -}
                                    recordToInsert =
                                        Dict.get (BaseAudience.getIdString key.base) tableItemsWithRequestAcc
                                            |> Maybe.map
                                                (\r ->
                                                    { r
                                                        | rowIds = Set.insert (AudienceItem.getIdString key.row.item) r.rowIds
                                                        , colIds = Set.insert (AudienceItem.getIdString key.col.item) r.colIds
                                                    }
                                                )
                                            |> Maybe.withDefault
                                                { rowIds = Set.singleton (AudienceItem.getIdString key.row.item)
                                                , colIds = Set.singleton (AudienceItem.getIdString key.col.item)
                                                }
                                in
                                Dict.insert (BaseAudience.getIdString key.base) recordToInsert tableItemsWithRequestAcc

                            else
                                tableItemsWithRequestAcc
                          , if willReloadIncompatibilities then
                                let
                                    recordToInsert =
                                        Dict.get (BaseAudience.getIdString key.base) tableIncompatibilitiesWithRequestAcc
                                            |> Maybe.map
                                                (\r ->
                                                    { r
                                                        | rowIds = Set.insert (AudienceItem.getIdString key.row.item) r.rowIds
                                                        , colIds = Set.insert (AudienceItem.getIdString key.col.item) r.colIds
                                                    }
                                                )
                                            |> Maybe.withDefault
                                                { rowIds = Set.singleton (AudienceItem.getIdString key.row.item)
                                                , colIds = Set.singleton (AudienceItem.getIdString key.col.item)
                                                }
                                in
                                Dict.insert (BaseAudience.getIdString key.base) recordToInsert tableIncompatibilitiesWithRequestAcc

                            else
                                tableIncompatibilitiesWithRequestAcc
                          )
                        )

                    else if crosstabTableLoadingConfig.clearAndCancelNotReloaded then
                        ( Crosstab.insert key
                            { cell
                                | data =
                                    case cell.data of
                                        AvAData _ ->
                                            AvAData
                                                { data = Tracked.NotAsked
                                                , incompatibilities = Tracked.NotAsked
                                                }

                                        AverageData _ ->
                                            AverageData Tracked.NotAsked

                                        DeviceBasedUsageData _ ->
                                            DeviceBasedUsageData Tracked.NotAsked
                            }
                            crosstabTableAcc
                        , maybeAddCancelRequestCommand cell crosstabTableCmdsAcc
                        , ( tableItemsWithRequestAcc, tableIncompatibilitiesWithRequestAcc )
                        )

                    else
                        ( crosstabTableAcc
                        , crosstabTableCmdsAcc
                        , ( tableItemsWithRequestAcc, tableIncompatibilitiesWithRequestAcc )
                        )
                )
                ( audienceCrosstab.crosstab
                , []
                , ( Dict.empty, Dict.empty )
                )
                audienceCrosstab.crosstab

        -- Updated Tracked.Loading TOTAL cells that are being fetched & commands that this will fire
        ( newCrosstabTotals, newCrosstabTotalsCmds, ( totalItemsWithRequest, totalIncompatibilitiesWithRequest ) ) =
            Dict.Any.foldl
                (\( audienceItem, baseAudience ) cell ( totalsAcc, totalsCmdsAcc, ( totalItemsWithRequestAcc, totalIncompatibilitiesWithRequestAcc ) ) ->
                    let
                        willReloadThisCell : Bool
                        willReloadThisCell =
                            crosstabTotalsLoadingConfig.shouldReloadCell ( audienceItem, baseAudience ) cell

                        isTotalVsTotalCell : ( AudienceItem, BaseAudience ) -> Bool
                        isTotalVsTotalCell ( item, _ ) =
                            AudienceItem.totalItem == item

                        willReloadIncompatibilities : Bool
                        willReloadIncompatibilities =
                            not (isTotalVsTotalCell ( audienceItem, baseAudience )) && crosstabTotalsLoadingConfig.shouldReloadIncompatibilities ( audienceItem, baseAudience ) cell

                        hasLocationsAndWaves : Bool
                        hasLocationsAndWaves =
                            (not <| Set.Any.isEmpty audienceCrosstab.activeWaves) && (not <| Set.Any.isEmpty audienceCrosstab.activeLocations)

                        additionalCommandsToAdd : List Command
                        additionalCommandsToAdd =
                            let
                                trackerIdForCurrentItem : Tracked.TrackerId
                                trackerIdForCurrentItem =
                                    generateTrackerId
                                        audienceCrosstab.activeWaves
                                        audienceCrosstab.activeLocations
                                        baseAudience
                                        audienceItem
                                        AudienceItem.totalItem
                            in
                            if Set.member (AudienceItem.getIdString audienceItem) rowItemIdSet then
                                case AudienceItem.getDefinition audienceItem of
                                    Expression _ ->
                                        []

                                    Average avg ->
                                        if willReloadThisCell then
                                            [ MakeHttpRequest trackerIdForCurrentItem
                                                audienceCrosstab.activeWaves
                                                audienceCrosstab.activeLocations
                                                baseAudience
                                                (TotalColAverageRowRequest
                                                    { average = avg
                                                    , getData =
                                                        \unit ->
                                                            { row = audienceItem
                                                            , rowAverage = avg
                                                            , rowUnit = unit
                                                            }
                                                    }
                                                )
                                            ]

                                        else
                                            []

                                    DeviceBasedUsage dbu ->
                                        if willReloadThisCell then
                                            [ MakeHttpRequest trackerIdForCurrentItem
                                                audienceCrosstab.activeWaves
                                                audienceCrosstab.activeLocations
                                                baseAudience
                                                (TotalColDbuRowRequest
                                                    { average = AvgWithoutSuffixes (DeviceBasedUsage.getQuestionCode dbu)
                                                    , getData =
                                                        \unit ->
                                                            { row = audienceItem
                                                            , rowAverage = AvgWithoutSuffixes (DeviceBasedUsage.getQuestionCode dbu)
                                                            , rowUnit = unit
                                                            }
                                                    }
                                                )
                                            ]

                                        else
                                            []

                            else if Set.member (AudienceItem.getIdString audienceItem) colItemIdSet then
                                case AudienceItem.getDefinition audienceItem of
                                    Expression _ ->
                                        []

                                    Average avg ->
                                        if willReloadThisCell then
                                            [ MakeHttpRequest trackerIdForCurrentItem
                                                audienceCrosstab.activeWaves
                                                audienceCrosstab.activeLocations
                                                baseAudience
                                                (TotalRowAverageColRequest
                                                    { average = avg
                                                    , getData =
                                                        \unit ->
                                                            { col = audienceItem
                                                            , colAverage = avg
                                                            , colUnit = unit
                                                            }
                                                    }
                                                )
                                            ]

                                        else
                                            []

                                    DeviceBasedUsage dbu ->
                                        if willReloadThisCell then
                                            [ MakeHttpRequest trackerIdForCurrentItem
                                                audienceCrosstab.activeWaves
                                                audienceCrosstab.activeLocations
                                                baseAudience
                                                (TotalRowDbuColRequest
                                                    { average = AvgWithoutSuffixes (DeviceBasedUsage.getQuestionCode dbu)
                                                    , getData =
                                                        \unit ->
                                                            { col = audienceItem
                                                            , colAverage = AvgWithoutSuffixes (DeviceBasedUsage.getQuestionCode dbu)
                                                            , colUnit = unit
                                                            }
                                                    }
                                                )
                                            ]

                                        else
                                            []

                            else
                                []
                    in
                    if hasLocationsAndWaves && (willReloadThisCell || willReloadIncompatibilities) then
                        ( Dict.Any.insert ( audienceItem, baseAudience )
                            { cell
                                | data =
                                    let
                                        trackerIdForCurrentItem : Tracked.TrackerId
                                        trackerIdForCurrentItem =
                                            generateTrackerId
                                                audienceCrosstab.activeWaves
                                                audienceCrosstab.activeLocations
                                                baseAudience
                                                audienceItem
                                                AudienceItem.totalItem
                                    in
                                    case cell.data of
                                        AvAData cellData ->
                                            AvAData
                                                { cellData
                                                    | data =
                                                        if willReloadThisCell then
                                                            Tracked.loading
                                                                bulkRequestTrackerId

                                                        else
                                                            cellData.data
                                                    , incompatibilities =
                                                        if willReloadIncompatibilities then
                                                            Tracked.loading
                                                                (bulkRequestTrackerId
                                                                    ++ "--incompatibilities"
                                                                )

                                                        else
                                                            cellData.incompatibilities
                                                }

                                        AverageData _ ->
                                            AverageData <|
                                                Tracked.loading trackerIdForCurrentItem

                                        DeviceBasedUsageData _ ->
                                            DeviceBasedUsageData <|
                                                Tracked.loading trackerIdForCurrentItem
                            }
                            totalsAcc
                        , totalsCmdsAcc ++ additionalCommandsToAdd
                        , ( if willReloadThisCell then
                                if Set.member (AudienceItem.getIdString audienceItem) rowItemIdSet then
                                    let
                                        recordToInsert =
                                            Dict.get (BaseAudience.getIdString baseAudience) totalItemsWithRequestAcc
                                                |> Maybe.map
                                                    (\r ->
                                                        { r
                                                            | rowIds = Set.insert (AudienceItem.getIdString audienceItem) r.rowIds
                                                        }
                                                    )
                                                |> Maybe.withDefault
                                                    { rowIds = Set.singleton (AudienceItem.getIdString audienceItem)
                                                    , colIds = Set.empty
                                                    }
                                    in
                                    Dict.insert (BaseAudience.getIdString baseAudience) recordToInsert totalItemsWithRequestAcc

                                else
                                    let
                                        recordToInsert =
                                            Dict.get (BaseAudience.getIdString baseAudience) totalItemsWithRequestAcc
                                                |> Maybe.map
                                                    (\r ->
                                                        { r
                                                            | colIds = Set.insert (AudienceItem.getIdString audienceItem) r.colIds
                                                        }
                                                    )
                                                |> Maybe.withDefault
                                                    { rowIds = Set.empty
                                                    , colIds = Set.singleton (AudienceItem.getIdString audienceItem)
                                                    }
                                    in
                                    Dict.insert (BaseAudience.getIdString baseAudience) recordToInsert totalItemsWithRequestAcc

                            else
                                totalItemsWithRequestAcc
                          , if willReloadIncompatibilities then
                                if Set.member (AudienceItem.getIdString audienceItem) rowItemIdSet then
                                    let
                                        recordToInsert =
                                            Dict.get (BaseAudience.getIdString baseAudience) totalIncompatibilitiesWithRequestAcc
                                                |> Maybe.map
                                                    (\r ->
                                                        { r
                                                            | rowIds = Set.insert (AudienceItem.getIdString audienceItem) r.rowIds
                                                        }
                                                    )
                                                |> Maybe.withDefault
                                                    { rowIds = Set.singleton (AudienceItem.getIdString audienceItem)
                                                    , colIds = Set.empty
                                                    }
                                    in
                                    Dict.insert (BaseAudience.getIdString baseAudience) recordToInsert totalIncompatibilitiesWithRequestAcc

                                else
                                    let
                                        recordToInsert =
                                            Dict.get (BaseAudience.getIdString baseAudience) totalIncompatibilitiesWithRequestAcc
                                                |> Maybe.map
                                                    (\r ->
                                                        { r
                                                            | colIds = Set.insert (AudienceItem.getIdString audienceItem) r.colIds
                                                        }
                                                    )
                                                |> Maybe.withDefault
                                                    { rowIds = Set.empty
                                                    , colIds = Set.singleton (AudienceItem.getIdString audienceItem)
                                                    }
                                    in
                                    Dict.insert (BaseAudience.getIdString baseAudience) recordToInsert totalIncompatibilitiesWithRequestAcc

                            else
                                totalIncompatibilitiesWithRequestAcc
                          )
                        )

                    else if crosstabTableLoadingConfig.clearAndCancelNotReloaded then
                        ( Dict.Any.insert ( audienceItem, baseAudience )
                            { cell
                                | data =
                                    case cell.data of
                                        AvAData _ ->
                                            AvAData
                                                { data = Tracked.NotAsked
                                                , incompatibilities = Tracked.NotAsked
                                                }

                                        AverageData _ ->
                                            AverageData Tracked.NotAsked

                                        DeviceBasedUsageData _ ->
                                            DeviceBasedUsageData Tracked.NotAsked
                            }
                            totalsAcc
                        , maybeAddCancelRequestCommand cell totalsCmdsAcc
                        , ( totalItemsWithRequestAcc, totalIncompatibilitiesWithRequestAcc )
                        )

                    else
                        ( totalsAcc
                        , totalsCmdsAcc
                        , ( totalItemsWithRequestAcc, totalIncompatibilitiesWithRequestAcc )
                        )
                )
                ( audienceCrosstab.totals
                , []
                , ( Dict.empty, Dict.empty )
                )
                audienceCrosstab.totals

        -- Whole /intersection request that we'll be doing based on visible cells
        ( makeBulkRequestCommand, makeIncompatibilitiesBulkRequestCommand ) =
            let
                finalRowsAndColsWithRequest =
                    Dict.merge
                        Dict.insert
                        (\key a b ->
                            Dict.insert key
                                { rowIds = Set.union a.rowIds b.rowIds
                                , colIds = Set.union a.colIds b.colIds
                                }
                        )
                        Dict.insert
                        tableItemsWithRequest
                        totalItemsWithRequest
                        Dict.empty

                finalRowsAndColsIncompatibilitiesWithRequest =
                    Dict.merge
                        Dict.insert
                        (\key a b ->
                            Dict.insert key
                                { rowIds = Set.union a.rowIds b.rowIds
                                , colIds = Set.union a.colIds b.colIds
                                }
                        )
                        Dict.insert
                        tableIncompatibilitiesWithRequest
                        totalIncompatibilitiesWithRequest
                        Dict.empty
            in
            ( Dict.toList finalRowsAndColsWithRequest
                |> List.map
                    (\( baseAudienceId, record ) ->
                        let
                            -- For every baseAudienceId we grab the rows and cols that need a request and push them into the BulkRequest
                            rowsThatWillBeSent =
                                List.filter
                                    (\key ->
                                        Set.member
                                            (AudienceItem.getIdString key.item)
                                            record.rowIds
                                    )
                                    allTheRows

                            rowExprsThatWillBeSent =
                                List.filterMap
                                    (\key ->
                                        case AudienceItem.getDefinition key.item of
                                            Expression expr ->
                                                Just expr

                                            Average _ ->
                                                Nothing

                                            DeviceBasedUsage _ ->
                                                Nothing
                                    )
                                    rowsThatWillBeSent

                            colsThatWillBeSent =
                                List.filter
                                    (\key ->
                                        Set.member
                                            (AudienceItem.getIdString key.item)
                                            record.colIds
                                    )
                                    allTheCols

                            colExprsThatWillBeSent =
                                List.filterMap
                                    (\key ->
                                        case AudienceItem.getDefinition key.item of
                                            Expression expr ->
                                                Just expr

                                            Average _ ->
                                                Nothing

                                            DeviceBasedUsage _ ->
                                                Nothing
                                    )
                                    colsThatWillBeSent

                            baseThatWillBeSent =
                                audienceCrosstab.bases
                                    |> Zipper.toList
                                    |> List.foldl
                                        (\base acc ->
                                            if BaseAudience.getIdString (unwrapCrosstabBase base) == baseAudienceId then
                                                Just (unwrapCrosstabBase base)

                                            else
                                                acc
                                        )
                                        Nothing
                                    |> Maybe.withDefault currentBaseAudience
                        in
                        if List.isEmpty rowsThatWillBeSent && List.isEmpty colsThatWillBeSent then
                            let
                                trackerIdForCurrentItem : Tracked.TrackerId
                                trackerIdForCurrentItem =
                                    generateTrackerId
                                        audienceCrosstab.activeWaves
                                        audienceCrosstab.activeLocations
                                        baseThatWillBeSent
                                        AudienceItem.totalItem
                                        AudienceItem.totalItem
                            in
                            -- In case the request would send nor rows nor columns, we have to request for the TotalVsTotal case, otherwise the cell would always be loading
                            MakeHttpRequest trackerIdForCurrentItem
                                audienceCrosstab.activeWaves
                                audienceCrosstab.activeLocations
                                baseThatWillBeSent
                                TotalVsTotalRequest

                        else
                            MakeHttpRequest bulkRequestTrackerId
                                audienceCrosstab.activeWaves
                                audienceCrosstab.activeLocations
                                baseThatWillBeSent
                                (CrosstabBulkAvARequest
                                    { rows = rowsThatWillBeSent
                                    , cols = colsThatWillBeSent
                                    , rowExprs = rowExprsThatWillBeSent
                                    , colExprs = colExprsThatWillBeSent
                                    }
                                )
                    )
            , Dict.toList finalRowsAndColsIncompatibilitiesWithRequest
                |> List.filterMap
                    (\( baseAudienceId, record ) ->
                        let
                            rowsThatWillBeSent =
                                List.filter
                                    (\key ->
                                        Set.member
                                            (AudienceItem.getIdString key.item)
                                            record.rowIds
                                    )
                                    allTheRows

                            rowExprsThatWillBeSent =
                                List.filterMap
                                    (\key ->
                                        case AudienceItem.getDefinition key.item of
                                            Expression expr ->
                                                Just expr

                                            Average _ ->
                                                Nothing

                                            DeviceBasedUsage _ ->
                                                Nothing
                                    )
                                    rowsThatWillBeSent

                            colsThatWillBeSent =
                                List.filter
                                    (\key ->
                                        Set.member
                                            (AudienceItem.getIdString key.item)
                                            record.colIds
                                    )
                                    allTheCols

                            colExprsThatWillBeSent =
                                List.filterMap
                                    (\key ->
                                        case AudienceItem.getDefinition key.item of
                                            Expression expr ->
                                                Just expr

                                            Average _ ->
                                                Nothing

                                            DeviceBasedUsage _ ->
                                                Nothing
                                    )
                                    colsThatWillBeSent

                            baseThatWillBeSent =
                                audienceCrosstab.bases
                                    |> Zipper.toList
                                    |> List.foldl
                                        (\base acc ->
                                            if BaseAudience.getIdString (unwrapCrosstabBase base) == baseAudienceId then
                                                Just (unwrapCrosstabBase base)

                                            else
                                                acc
                                        )
                                        Nothing
                                    |> Maybe.withDefault currentBaseAudience
                        in
                        if List.isEmpty rowsThatWillBeSent && List.isEmpty colsThatWillBeSent then
                            Nothing

                        else
                            Just <|
                                MakeHttpRequest (bulkRequestTrackerId ++ "--incompatibilities")
                                    audienceCrosstab.activeWaves
                                    audienceCrosstab.activeLocations
                                    baseThatWillBeSent
                                    (IncompatibilityBulkRequest
                                        { rows = rowsThatWillBeSent
                                        , cols = colsThatWillBeSent
                                        , rowExprs = rowExprsThatWillBeSent
                                        , colExprs = colExprsThatWillBeSent
                                        }
                                    )
                    )
            )
    in
    ( AudienceCrosstab
        { audienceCrosstab
            | crosstab = newCrosstabTable
            , totals = newCrosstabTotals
        }
    , makeBulkRequestCommand
        ++ makeIncompatibilitiesBulkRequestCommand
        ++ newCrosstabTableCmds
        ++ newCrosstabTotalsCmds
    )


totalKey : Key
totalKey =
    { item = AudienceItem.totalItem
    , isSelected = False
    }


indexedMap : (( Int, Int ) -> BaseAudience -> Cell -> Cell) -> AudienceCrosstab -> AudienceCrosstab
indexedMap fn (AudienceCrosstab ac) =
    let
        processColumns rowIndex row baseAudience acc =
            let
                totalRowIndexes =
                    ( rowIndex, 0 )

                updateCell indexes =
                    Maybe.map (fn indexes baseAudience)
            in
            (totalKey :: Crosstab.getColumns ac.crosstab)
                |> List.indexedFoldl
                    (\colIndex col ( totals, crosstab ) ->
                        let
                            key =
                                { row = row, col = col, base = baseAudience }

                            indexes =
                                ( rowIndex, colIndex )
                        in
                        ( if rowIndex == 0 then
                            Dict.Any.update ( col.item, baseAudience ) (updateCell indexes) totals

                          else
                            totals
                        , Crosstab.update key (updateCell indexes) crosstab
                        )
                    )
                    (Tuple.mapFirst (Dict.Any.update ( row.item, baseAudience ) (updateCell totalRowIndexes)) acc)

        ( newTotals, newCrosstab ) =
            (totalKey :: Crosstab.getRows ac.crosstab)
                |> List.indexedFoldl
                    (\rowIndex row acc ->
                        List.foldl (processColumns rowIndex row) acc (basesToList ac.bases)
                    )
                    ( ac.totals
                    , ac.crosstab
                    )
    in
    AudienceCrosstab
        { ac
            | crosstab = newCrosstab
            , totals = newTotals
        }


setCellsVisibility : Bool -> VisibleCells -> AudienceCrosstab -> AudienceCrosstab
setCellsVisibility recalculate visibleCells (AudienceCrosstab ac) =
    let
        currentBase =
            Zipper.current ac.bases |> unwrapCrosstabBase

        updateCell ( rowIndex, columnIndex ) base cell =
            if base == currentBase then
                let
                    indexes =
                        { rowIndex = rowIndex
                        , columnIndex = columnIndex
                        }
                in
                { cell
                    | isVisible = isCellVisible visibleCells 0 indexes
                    , shouldBeLoaded = isCellVisible visibleCells ac.loadingBoundaries indexes
                }

            else
                { cell | isVisible = False, shouldBeLoaded = False }
    in
    if recalculate then
        indexedMap updateCell (AudienceCrosstab { ac | visibleCells = visibleCells })

    else
        AudienceCrosstab { ac | visibleCells = visibleCells }


setLoadNotAskedTotalRows : AudienceCrosstab -> AudienceCrosstab
setLoadNotAskedTotalRows (AudienceCrosstab r) =
    let
        crosstabRows =
            Crosstab.getRows r.crosstab
                |> List.map keyToComparable
                |> Set.fromList
    in
    updateTotals
        (Dict.Any.map
            (\( item, _ ) cell ->
                if Set.member (audienceItemToComparable item) crosstabRows && isCellNotAsked cell then
                    { cell | shouldBeLoaded = True }

                else
                    cell
            )
        )
        (AudienceCrosstab r)


setRowShouldBeLoaded : AudienceItemId -> AudienceCrosstab -> AudienceCrosstab
setRowShouldBeLoaded rowId audienceCrosstab =
    updateCrosstab
        (Crosstab.map
            (\{ row } cell ->
                if
                    isCellNotAsked cell
                        && (AudienceItem.getId row.item == rowId)
                then
                    { cell | shouldBeLoaded = True }

                else
                    cell
            )
        )
        audienceCrosstab


setLoadNotAskedTotalColumns : AudienceCrosstab -> AudienceCrosstab
setLoadNotAskedTotalColumns (AudienceCrosstab r) =
    let
        crosstabColumns =
            Crosstab.getColumns r.crosstab
                |> List.map keyToComparable
                |> Set.fromList
    in
    updateTotals
        (Dict.Any.map
            (\( item, _ ) cell ->
                if Set.member (audienceItemToComparable item) crosstabColumns && isCellNotAsked cell then
                    { cell | shouldBeLoaded = True }

                else
                    cell
            )
        )
        (AudienceCrosstab r)


setColumnShouldBeLoaded : AudienceItemId -> AudienceCrosstab -> AudienceCrosstab
setColumnShouldBeLoaded columnId audienceCrosstab =
    updateCrosstab
        (Crosstab.map
            (\{ col } cell ->
                if
                    isCellNotAsked cell
                        && (AudienceItem.getId col.item == columnId)
                then
                    { cell | shouldBeLoaded = True }

                else
                    cell
            )
        )
        audienceCrosstab


forceCellShouldBeLoaded :
    { row : Key
    , col : Key
    , base : BaseAudience
    }
    -> AudienceCrosstab
    -> AudienceCrosstab
forceCellShouldBeLoaded key audienceCrosstab =
    updateCrosstab
        (Crosstab.map
            (\key_ cell ->
                if key == key_ then
                    { cell | shouldBeLoaded = True }

                else
                    cell
            )
        )
        audienceCrosstab


forceTotalCellShouldBeLoaded :
    ( AudienceItem, BaseAudience )
    -> AudienceCrosstab
    -> AudienceCrosstab
forceTotalCellShouldBeLoaded key audienceCrosstab =
    updateTotals
        (Dict.Any.map
            (\key_ cell ->
                if key == key_ then
                    { cell | shouldBeLoaded = True }

                else
                    cell
            )
        )
        audienceCrosstab


getVisibleCellsForRender : AudienceCrosstab -> VisibleCells
getVisibleCellsForRender (AudienceCrosstab ac) =
    let
        { rowCount, colCount } =
            getDimensionsWithTotals (AudienceCrosstab ac)
    in
    if rowCount > limitForFullRender || colCount > limitForFullRender then
        ac.visibleCells

    else
        { topLeftRow = 0
        , topLeftCol = 0
        , bottomRightRow = rowCount + 1
        , bottomRightCol = colCount + 1
        , frozenRows = ac.visibleCells.frozenRows
        , frozenCols = ac.visibleCells.frozenCols
        }


getVisibleCells : AudienceCrosstab -> VisibleCells
getVisibleCells (AudienceCrosstab ac) =
    ac.visibleCells


isCellVisible : VisibleCells -> Int -> CellIndexes -> Bool
isCellVisible visibleCells boundary { rowIndex, columnIndex } =
    let
        topLeftRow =
            visibleCells.topLeftRow - boundary

        topLeftCol =
            visibleCells.topLeftCol - boundary

        bottomRightRow =
            visibleCells.bottomRightRow + boundary

        bottomRightCol =
            visibleCells.bottomRightCol + boundary

        isAFrozenRow =
            (columnIndex >= topLeftCol && columnIndex <= bottomRightCol)
                && (rowIndex
                        >= 0
                        && rowIndex
                        <= (visibleCells.frozenRows - 1)
                   )

        isAFrozenCol =
            (rowIndex >= topLeftRow && rowIndex <= bottomRightRow)
                && (columnIndex
                        >= 0
                        && columnIndex
                        <= (visibleCells.frozenCols - 1)
                   )

        isAFrozenCombinedCell =
            (rowIndex >= 0 && rowIndex <= (visibleCells.frozenRows - 1))
                && (columnIndex >= 0 && columnIndex <= (visibleCells.frozenCols - 1))
    in
    ((topLeftRow <= rowIndex && rowIndex <= bottomRightRow)
        && (topLeftCol <= columnIndex && columnIndex <= bottomRightCol)
    )
        || isAFrozenRow
        || isAFrozenCol
        || isAFrozenCombinedCell


addAndMapMaybe : (a -> b) -> Maybe a -> List b -> List b
addAndMapMaybe toValue maybe list =
    case maybe of
        Just a ->
            toValue a :: list

        Nothing ->
            list


{-| If the cell represents in-progress request, add a command to cancel the request to the list, otherwise do nothing.
-}
maybeAddCancelRequestCommand : Cell -> List Command -> List Command
maybeAddCancelRequestCommand trackedCell commands =
    case trackedCell.data of
        AvAData data ->
            commands
                |> addAndMapMaybe CancelHttpRequest (Tracked.getTrackerId data.data)
                |> addAndMapMaybe CancelHttpRequest (Tracked.getTrackerId data.incompatibilities)

        AverageData data ->
            commands
                |> addAndMapMaybe CancelHttpRequest (Tracked.getTrackerId data)

        DeviceBasedUsageData data ->
            commands
                |> addAndMapMaybe CancelHttpRequest (Tracked.getTrackerId data)


setLoadingCellNotAsked : Cell -> Cell
setLoadingCellNotAsked cell =
    case cell.data of
        AvAData cellData ->
            if Tracked.isSuccess cellData.data && Tracked.isSuccess cellData.incompatibilities then
                cell

            else
                { cell | data = AvAData { cellData | data = Tracked.NotAsked, incompatibilities = Tracked.NotAsked } }

        AverageData data ->
            if Tracked.isSuccess data then
                cell

            else
                { cell | data = AverageData Tracked.NotAsked }

        DeviceBasedUsageData data ->
            if Tracked.isSuccess data then
                cell

            else
                { cell | data = DeviceBasedUsageData Tracked.NotAsked }


setCellNotAsked : Cell -> Cell
setCellNotAsked cell =
    { cell
        | data =
            case cell.data of
                AvAData cellData ->
                    AvAData { cellData | data = Tracked.NotAsked, incompatibilities = Tracked.NotAsked }

                AverageData _ ->
                    AverageData Tracked.NotAsked

                DeviceBasedUsageData _ ->
                    DeviceBasedUsageData Tracked.NotAsked
    }


setCrosstabLoadingCellsAsNotLoaded : CrosstabTable -> CrosstabTable
setCrosstabLoadingCellsAsNotLoaded crosstab =
    Crosstab.map (\_ -> setLoadingCellNotAsked) crosstab


setTotalsLoadingCellsAsNotLoaded : Totals -> Totals
setTotalsLoadingCellsAsNotLoaded totals =
    Dict.Any.map (\_ -> setLoadingCellNotAsked) totals


initFromProject : Posix -> Int -> Int -> XBProjectFullyLoaded -> Result ErrorAddingRowOrColumn ( AudienceCrosstab, List Command )
initFromProject posix limit loadingBoundaries project =
    let
        initialSeed =
            Random.initialSeed <| Time.posixToMillis posix

        ( bases, seedAfterBases ) =
            NonemptyList.foldr
                (\baseData ( items, s ) ->
                    BaseAudience.fromSavedProject s baseData
                        |> Tuple.mapFirst (\base -> base :: items)
                )
                ( [], initialSeed )
                project.data.bases
                |> Tuple.mapFirst
                    (NonemptyList.fromList
                        >> Maybe.withDefault (NonemptyList.singleton BaseAudience.default)
                    )

        basesCount =
            NonemptyList.length project.data.bases

        itemToKey item seed =
            AudienceItem.fromSavedProject item seed
                |> Tuple.mapFirst
                    (\generatedItem ->
                        { item = generatedItem
                        , isSelected = False
                        }
                    )
    in
    AudienceCrosstab
        { crosstab = emptyCrosstabTable
        , totals = initTotals bases
        , activeLocations = XB2.Share.Data.Id.setFromList project.data.locationCodes
        , activeWaves = XB2.Share.Data.Id.setFromList project.data.waveCodes
        , bases =
            {- This thing here sets the last base as DefaultBase, so we need to work
               around it
            -}
            NonemptyList.indexedMap
                (\index ->
                    if index == (basesCount - 1) then
                        DefaultBase

                    else
                        flip selectableBase False
                )
                bases
                |> Zipper.fromNonEmpty
                |> Zipper.end
        , limit = limit
        , loadingBoundaries = loadingBoundaries
        , visibleCells = defaultVisibleCells
        , keyMapping = computeKeyMapping emptyCrosstabTable
        , seed = seedAfterBases
        }
        |> addAudiencesPure { fixIdDuplicities = True }
            addColumns
            (List.map itemToKey project.data.columns)
        |> Result.andThen
            (addAudiencesPure { fixIdDuplicities = False }
                addRows
                (List.map itemToKey project.data.rows)
            )
        |> Result.map reloadAllCells


removeAudiences : List ( Direction, Key ) -> AudienceCrosstab -> ( AudienceCrosstab, List Command )
removeAudiences audiencesToRemove (AudienceCrosstab ({ crosstab, totals, visibleCells } as ac)) =
    let
        -- Pair of `Set ( Int, String )` with `( Int, String )` being comparable representation of `AudienceItemId`s
        ( idsOfRowsToRemove, idsOfColsToRemove ) =
            List.foldl
                (\( dir, key ) ( rids, cids ) ->
                    let
                        comparableId =
                            keyToComparable key
                    in
                    case dir of
                        Row ->
                            ( Set.insert comparableId rids
                            , cids
                            )

                        Column ->
                            ( rids
                            , Set.insert comparableId cids
                            )
                )
                ( Set.empty, Set.empty )
                audiencesToRemove

        idsOfTotalsToRemove : Set AudienceItemId.ComparableId
        idsOfTotalsToRemove =
            Set.union
                -- Only remove those Columns from totals, which are not among existing Rows
                (Set.diff idsOfColsToRemove (Crosstab.getRows crosstab |> List.map keyToComparable |> Set.fromList))
                -- Only remove those Rows    from totals, which are not among existing Columns
                (Set.diff idsOfRowsToRemove (Crosstab.getColumns crosstab |> List.map keyToComparable |> Set.fromList))

        newCrosstab =
            AudienceCrosstab
                { ac
                    | totals =
                        ac.totals
                            |> Dict.Any.filter (\( item, _ ) _ -> not <| Set.member (audienceItemToComparable item) idsOfTotalsToRemove)
                }
                |> updateCrosstab
                    (\crosstab_ ->
                        crosstab_
                            |> Crosstab.filterRows (\key -> not <| Set.member (keyToComparable key) idsOfRowsToRemove)
                            |> Crosstab.filterColumns (\key -> not <| Set.member (keyToComparable key) idsOfColsToRemove)
                    )

        crosstabCancelRequests =
            Crosstab.getRemovedValues crosstab (getCrosstab newCrosstab)
                |> List.foldr maybeAddCancelRequestCommand []

        allCancelRequests =
            Dict.Any.diff totals (getTotals newCrosstab)
                |> Dict.Any.values
                |> List.foldr maybeAddCancelRequestCommand crosstabCancelRequests
    in
    ( setCellsVisibility True visibleCells newCrosstab
    , allCancelRequests
    )


moveItemsToIndex : Direction -> Int -> MovableItems -> AudienceCrosstab -> Result ErrorAddingRowOrColumn ( AudienceCrosstab, List Command )
moveItemsToIndex moveTo index items ((AudienceCrosstab ac) as crosstab) =
    let
        keyToCell key =
            items
                |> NonemptyList.find (\( _, item ) -> item == key)
                |> Maybe.unwrap emptyCell (\( _, item ) -> { emptyCell | data = keyToNotAskedCellData item })

        ( otherDirection, moveFn_ ) =
            case moveTo of
                Row ->
                    ( Column, Crosstab.moveItemsToRowIndex keyToCell )

                Column ->
                    ( Row, Crosstab.moveItemsToColumnIndex keyToCell )

        anyFromOtherDirection =
            NonemptyList.any (Tuple.first >> (==) otherDirection) items

        ( rowsToMove, columnsToMove ) =
            items
                |> NonemptyList.foldl
                    (\( from, item ) ( accRows, accCols ) ->
                        if from == Row then
                            ( accRows ++ [ item ], accCols )

                        else
                            ( accRows, accCols ++ [ item ] )
                    )
                    ( [], [] )

        getCountOf colOrRowType =
            items
                |> NonemptyList.filterMap (Tuple.first >> Just >> Maybe.filter ((==) colOrRowType))
                |> Maybe.unwrap 0 NonemptyList.length

        itemsToAdd =
            { rows = rowsToMove, columns = columnsToMove }

        moveFn =
            moveFn_ index itemsToAdd (basesToList ac.bases)
    in
    if anyFromOtherDirection then
        let
            addedCols =
                if moveTo == Column then
                    getCountOf Row

                else
                    negate <| getCountOf Column

            addedRows =
                if moveTo == Row then
                    getCountOf Column

                else
                    negate <| getCountOf Row

            getKey : Key
            getKey =
                let
                    ( _, key ) =
                        NonemptyList.head items
                in
                key

            getAudienceIdFromKey : AudienceItem
            getAudienceIdFromKey =
                getKey.item

            base =
                Zipper.current ac.bases |> unwrapCrosstabBase

            tupleKey =
                ( getAudienceIdFromKey, base )
        in
        ifNotExceedingLimit { addedCols = addedCols, addedRows = addedRows } moveFn crosstab
            |> Result.map (setCellsVisibility True ac.visibleCells)
            |> Result.map (combineMethodsReloadTotal tupleKey)

    else
        ( updateCrosstab moveFn crosstab, [] )
            |> Ok


moveItemsToRowIndex : Int -> MovableItems -> AudienceCrosstab -> Result ErrorAddingRowOrColumn ( AudienceCrosstab, List Command )
moveItemsToRowIndex =
    moveItemsToIndex Row


moveItemsToColumnIndex : Int -> MovableItems -> AudienceCrosstab -> Result ErrorAddingRowOrColumn ( AudienceCrosstab, List Command )
moveItemsToColumnIndex =
    moveItemsToIndex Column


switchRowsAndColumns : AudienceCrosstab -> ( AudienceCrosstab, List Command )
switchRowsAndColumns (AudienceCrosstab ({ totals } as record)) =
    let
        swapRowColIntersectionValues cell =
            { cell
                | data =
                    mapIntersectResult
                        (AudienceIntersect.mapXBAudiences
                            AudienceIntersect.swapXBAudiences
                        )
                        cell.data
            }
    in
    AudienceCrosstab
        { record | totals = Dict.Any.map (always swapRowColIntersectionValues) totals }
        |> updateCrosstab (Crosstab.switchRowsAndColumns swapRowColIntersectionValues)
        |> setCellsVisibility True record.visibleCells
        |> reloadAllCells


cancelUnfinishedRequests : AudienceCrosstab -> List Command
cancelUnfinishedRequests crosstab =
    let
        getIds : AnyDict comparable k Cell -> List Tracked.TrackerId
        getIds =
            Dict.Any.values
                >> List.filterMap
                    (\cell ->
                        case cell.data of
                            AvAData { data, incompatibilities } ->
                                [ Tracked.getTrackerId data, Tracked.getTrackerId incompatibilities ]
                                    |> List.filterMap identity
                                    |> NonemptyList.fromList
                                    |> Maybe.map NonemptyList.toList

                            AverageData avgData ->
                                Maybe.map List.singleton <| Tracked.getTrackerId avgData

                            DeviceBasedUsageData dbuData ->
                                Maybe.map List.singleton <| Tracked.getTrackerId dbuData
                    )
                >> List.fastConcat

        totalCellIds =
            getIds <| getTotals crosstab

        cellIds =
            getIds <| Crosstab.getValues (getCrosstab crosstab)
    in
    totalCellIds
        |> List.append cellIds
        |> List.map CancelHttpRequest


updateCrosstab : (CrosstabTable -> CrosstabTable) -> AudienceCrosstab -> AudienceCrosstab
updateCrosstab f (AudienceCrosstab r) =
    let
        newCrosstab =
            f r.crosstab
    in
    AudienceCrosstab
        { r
            | crosstab = newCrosstab
            , keyMapping = computeKeyMapping newCrosstab
        }


updateTotals : (Totals -> Totals) -> AudienceCrosstab -> AudienceCrosstab
updateTotals f (AudienceCrosstab r) =
    AudienceCrosstab { r | totals = f r.totals }


insertCellData : CellData -> Cell -> Cell
insertCellData cellData cell =
    { cell
        | data =
            case ( cell.data, cellData ) of
                ( AvAData data, AvAData dataNew ) ->
                    AvAData { data | data = dataNew.data }

                ( AvAData _, AverageData _ ) ->
                    cellData

                ( AvAData _, DeviceBasedUsageData _ ) ->
                    cellData

                ( AverageData _, AverageData _ ) ->
                    cellData

                ( DeviceBasedUsageData _, DeviceBasedUsageData _ ) ->
                    cellData

                ( AverageData _, DeviceBasedUsageData _ ) ->
                    cellData

                ( DeviceBasedUsageData _, AverageData _ ) ->
                    cellData

                ( AverageData _, AvAData _ ) ->
                    cellData

                ( DeviceBasedUsageData _, AvAData _ ) ->
                    cellData
    }


insertCrosstabCell : { row : Key, col : Key, base : BaseAudience } -> CellData -> AudienceCrosstab -> AudienceCrosstab
insertCrosstabCell key cellData =
    updateCrosstab <|
        Crosstab.update key
            (Just << Maybe.unwrap { emptyCell | data = cellData } (insertCellData cellData))


insertTotalsCell : AudienceItem -> BaseAudience -> CellData -> AudienceCrosstab -> AudienceCrosstab
insertTotalsCell audienceItem base cellData =
    updateTotals <| Dict.Any.update ( audienceItem, base ) (Just << Maybe.unwrap { emptyCell | data = cellData } (insertCellData cellData))


insertCellAvaData : ({ data : CellDataResult, incompatibilities : Incompatibilities } -> { data : CellDataResult, incompatibilities : Incompatibilities }) -> CellData -> CellData
insertCellAvaData fn cellData =
    case cellData of
        AvAData data ->
            AvAData <| fn data

        AverageData _ ->
            cellData

        DeviceBasedUsageData _ ->
            cellData


incompatibilitiesCellInserter : Incompatibilities -> Maybe Cell -> Maybe Cell
incompatibilitiesCellInserter data =
    Maybe.unwrap (initCell Tracked.NotAsked data)
        (\cell ->
            { cell | data = insertCellAvaData (\d -> { d | incompatibilities = data }) cell.data }
        )
        >> Just


insertIncompatibilities : { row : Key, col : Key, base : BaseAudience } -> Incompatibilities -> AudienceCrosstab -> AudienceCrosstab
insertIncompatibilities key data =
    updateCrosstab <| Crosstab.update key (incompatibilitiesCellInserter data)


insertTotalIncompatibilities : AudienceItem -> BaseAudience -> Incompatibilities -> AudienceCrosstab -> AudienceCrosstab
insertTotalIncompatibilities audienceItem base data =
    updateTotals <| Dict.Any.update ( audienceItem, base ) (incompatibilitiesCellInserter data)


isEmpty : AudienceCrosstab -> Bool
isEmpty =
    Crosstab.isEmpty << getCrosstab


basesNotEdided : AudienceCrosstab -> Bool
basesNotEdided (AudienceCrosstab r) =
    r.bases
        |> Zipper.toList
        |> List.filter ((/=) initBase)
        |> List.isEmpty


getRows : AudienceCrosstab -> List Key
getRows =
    Crosstab.getRows << getCrosstab


isSelected : Key -> Bool
isSelected key =
    key.isSelected && not (AudienceItem.isAverageOrDbu key.item)


getSelectedRows : AudienceCrosstab -> List Key
getSelectedRows =
    List.filter isSelected << getRows


getNonselectedRows : AudienceCrosstab -> List Key
getNonselectedRows =
    List.filter (not << isSelected) << getRows


selectKey : Key -> Key
selectKey key =
    if AudienceItem.isAverageOrDbu key.item then
        key

    else
        { key | isSelected = True }


deselectKey : Key -> Key
deselectKey key =
    { key | isSelected = False }


selectRow : Key -> AudienceCrosstab -> AudienceCrosstab
selectRow key =
    replaceKey Row key (selectKey key)


selectWithShift : List Key -> (Key -> AudienceCrosstab -> AudienceCrosstab) -> Key -> AudienceCrosstab -> AudienceCrosstab
selectWithShift items select key ac =
    List.selectRange { isSelected = isSelected, itemToSelect = (==) key } items
        |> List.foldr select ac


selectRowWithShift : Key -> AudienceCrosstab -> AudienceCrosstab
selectRowWithShift key ac =
    selectWithShift (getRows ac) selectRow key ac


selectAllRows : AudienceCrosstab -> AudienceCrosstab
selectAllRows =
    updateCrosstab (Crosstab.updateRowKeys selectKey)


deselectRow : Key -> AudienceCrosstab -> AudienceCrosstab
deselectRow key =
    replaceKey Row key (deselectKey key)


deselectAllRows : AudienceCrosstab -> AudienceCrosstab
deselectAllRows =
    updateCrosstab (Crosstab.updateRowKeys deselectKey)


getColumns : AudienceCrosstab -> List Key
getColumns =
    Crosstab.getColumns << getCrosstab


selectColumn : Key -> AudienceCrosstab -> AudienceCrosstab
selectColumn key =
    replaceKey Column key (selectKey key)


selectColumnWithShift : Key -> AudienceCrosstab -> AudienceCrosstab
selectColumnWithShift key ac =
    selectWithShift (getColumns ac) selectColumn key ac


selectAllColumns : AudienceCrosstab -> AudienceCrosstab
selectAllColumns =
    updateCrosstab (Crosstab.updateColumnKeys selectKey)


deselectColumn : Key -> AudienceCrosstab -> AudienceCrosstab
deselectColumn key =
    replaceKey Column key (deselectKey key)


deselectAllColumns : AudienceCrosstab -> AudienceCrosstab
deselectAllColumns =
    updateCrosstab (Crosstab.updateColumnKeys deselectKey)


deselectAll : AudienceCrosstab -> AudienceCrosstab
deselectAll =
    updateCrosstab (Crosstab.updateKeys deselectKey)


anySelected : AudienceCrosstab -> Bool
anySelected ac =
    List.any isSelected (getRows ac)
        || List.any isSelected (getColumns ac)


isSelectedIfSelectable : Key -> Bool
isSelectedIfSelectable key =
    key.isSelected || AudienceItem.isAverageOrDbu key.item


allRowsSelected : AudienceCrosstab -> Bool
allRowsSelected =
    List.all isSelectedIfSelectable << getRows


allColumnsSelected : AudienceCrosstab -> Bool
allColumnsSelected =
    List.all isSelectedIfSelectable << getColumns


getSelectedColumns : AudienceCrosstab -> List Key
getSelectedColumns =
    List.filter isSelected << getColumns


getNonselectedColumns : AudienceCrosstab -> List Key
getNonselectedColumns =
    List.filter (not << isSelected) << getColumns


rowCountWithoutTotals : AudienceCrosstab -> Int
rowCountWithoutTotals =
    Crosstab.rowCount << getCrosstab


colCountWithoutTotals : AudienceCrosstab -> Int
colCountWithoutTotals =
    Crosstab.colCount << getCrosstab


selectableColCountWithoutTotals : AudienceCrosstab -> Int
selectableColCountWithoutTotals =
    List.length << List.filter (not << AudienceItem.isAverageOrDbu << .item) << getColumns


selectableRowCountWithoutTotals : AudienceCrosstab -> Int
selectableRowCountWithoutTotals =
    List.length << List.filter (not << AudienceItem.isAverageOrDbu << .item) << getRows


type alias AffixedItemCounts =
    { affixedRows : Int
    , affixedColumns : Int
    }


type alias EditedItemCounts =
    { editedRows : Int
    , editedColumns : Int
    }


type alias AffixGroupItem =
    -- TODO perhaps start using UUIDs as the indexes get unwieldy?
    { oldExpression : Expression
    , oldItem : AudienceItem
    , direction : Direction
    , newExpression : Expression
    , expressionBeingAffixed : Expression
    , newCaption : Caption
    }


type alias EditGroupItem =
    { oldExpression : Expression
    , oldItem : AudienceItem
    , direction : Direction
    , newExpression : Expression
    , expressionBeingEdited : Expression
    , newCaption : Caption
    }


affixGroups :
    List AffixGroupItem
    -> AudienceCrosstab
    -> ( AudienceCrosstab, { commands : List Command, counts : AffixedItemCounts } )
affixGroups groupsToSave (AudienceCrosstab r) =
    let
        toKey item =
            { item = item
            , isSelected = False
            }

        items :
            { affixedRows : AnySet AudienceItemId.ComparableId Key
            , affixedColumns : AnySet AudienceItemId.ComparableId Key
            }
        items =
            List.foldr
                (\{ direction, oldItem, newCaption, newExpression } acc ->
                    let
                        newItem =
                            AudienceItem.setCaption newCaption oldItem
                                |> AudienceItem.setDefinition (Expression newExpression)
                    in
                    case direction of
                        Row ->
                            { acc | affixedRows = Set.Any.insert (toKey newItem) acc.affixedRows }

                        Column ->
                            { acc | affixedColumns = Set.Any.insert (toKey newItem) acc.affixedColumns }
                )
                { affixedRows = Set.Any.empty keyToComparable
                , affixedColumns = Set.Any.empty keyToComparable
                }
                groupsToSave

        updateK key =
            Set.Any.get key items.affixedRows
                |> Maybe.orElseLazy (\() -> Set.Any.get key items.affixedColumns)
                |> Maybe.withDefault key

        invalidate { row, col } oldVal =
            if
                Set.Any.member row items.affixedRows
                    || Set.Any.member col items.affixedColumns
            then
                setCellNotAsked oldVal

            else
                oldVal
    in
    AudienceCrosstab
        { r
            | totals =
                -- on collision, preference is given to the first dict.
                -- this is essentially an UPSERT.
                Dict.Any.union
                    (Set.Any.foldr
                        (\{ item } accTotals ->
                            r.bases
                                |> Zipper.toList
                                |> List.foldl
                                    (\cBase ->
                                        let
                                            base =
                                                unwrapCrosstabBase cBase
                                        in
                                        Dict.Any.get ( item, base ) r.totals
                                            |> Maybe.unwrap
                                                emptyCell
                                                setCellNotAsked
                                            |> Dict.Any.insert ( item, base )
                                    )
                                    accTotals
                        )
                        (Dict.Any.removeAll r.totals)
                        (Set.Any.union items.affixedRows items.affixedColumns)
                    )
                    r.totals
        }
        |> updateCrosstab
            (\crosstab ->
                crosstab
                    |> Crosstab.map invalidate
                    |> Crosstab.updateKeys updateK
            )
        |> reloadNotLoadedCells
        |> Tuple.mapSecond
            (\commands ->
                { commands = commands
                , counts =
                    { affixedRows = Set.Any.size items.affixedRows
                    , affixedColumns = Set.Any.size items.affixedColumns
                    }
                }
            )


editGroups :
    List EditGroupItem
    -> AudienceCrosstab
    -> ( AudienceCrosstab, { commands : List Command, counts : EditedItemCounts } )
editGroups groupsToSave (AudienceCrosstab r) =
    let
        toKey item =
            { item = item
            , isSelected = False
            }

        items :
            { editedRows : AnySet AudienceItemId.ComparableId Key
            , editedColumns : AnySet AudienceItemId.ComparableId Key
            }
        items =
            List.foldr
                (\{ direction, oldItem, newCaption, newExpression } acc ->
                    let
                        newItem =
                            AudienceItem.setCaption newCaption oldItem
                                |> AudienceItem.setDefinition (Expression newExpression)
                    in
                    case direction of
                        Row ->
                            { acc | editedRows = Set.Any.insert (toKey newItem) acc.editedRows }

                        Column ->
                            { acc | editedColumns = Set.Any.insert (toKey newItem) acc.editedColumns }
                )
                { editedRows = Set.Any.empty keyToComparable
                , editedColumns = Set.Any.empty keyToComparable
                }
                groupsToSave

        updateK key =
            Set.Any.get key items.editedRows
                |> Maybe.orElseLazy (\() -> Set.Any.get key items.editedColumns)
                |> Maybe.withDefault key

        invalidate { row, col } oldVal =
            if
                Set.Any.member row items.editedRows
                    || Set.Any.member col items.editedColumns
            then
                setCellNotAsked oldVal

            else
                oldVal
    in
    AudienceCrosstab
        { r
            | totals =
                -- on collision, preference is given to the first dict.
                -- this is essentially an UPSERT.
                Dict.Any.union
                    (Set.Any.foldr
                        (\{ item } accTotals ->
                            r.bases
                                |> Zipper.toList
                                |> List.foldl
                                    (\cBase ->
                                        let
                                            base =
                                                unwrapCrosstabBase cBase
                                        in
                                        Dict.Any.get ( item, base ) r.totals
                                            |> Maybe.unwrap
                                                emptyCell
                                                setCellNotAsked
                                            |> Dict.Any.insert ( item, base )
                                    )
                                    accTotals
                        )
                        (Dict.Any.removeAll r.totals)
                        (Set.Any.union items.editedRows items.editedColumns)
                    )
                    r.totals
        }
        |> updateCrosstab
            (\crosstab ->
                crosstab
                    |> Crosstab.map invalidate
                    |> Crosstab.updateKeys updateK
            )
        |> reloadNotLoadedCells
        |> Tuple.mapSecond
            (\commands ->
                { commands = commands
                , counts =
                    { editedRows = Set.Any.size items.editedRows
                    , editedColumns = Set.Any.size items.editedColumns
                    }
                }
            )


replaceItem : Direction -> AudienceItem -> AudienceItem -> AudienceCrosstab -> AudienceCrosstab
replaceItem direction old new =
    let
        updateFn =
            case direction of
                Row ->
                    Crosstab.updateRowKeys

                Column ->
                    Crosstab.updateColumnKeys

        f key =
            if key.item == old then
                { key | item = new }

            else
                key
    in
    updateCrosstab (updateFn f)


replaceKey : Direction -> Key -> Key -> AudienceCrosstab -> AudienceCrosstab
replaceKey direction old new =
    let
        updateFn =
            case direction of
                Row ->
                    Crosstab.updateRowKeys

                Column ->
                    Crosstab.updateColumnKeys

        f key =
            if key.item == old.item then
                new

            else
                key
    in
    updateCrosstab (updateFn f)


isCellSuccess : Cell -> Bool
isCellSuccess cell =
    case cell.data of
        AvAData { data } ->
            Tracked.isSuccess data

        AverageData data ->
            Tracked.isSuccess data

        DeviceBasedUsageData data ->
            Tracked.isSuccess data


isCellDataFailure : CellData -> Bool
isCellDataFailure cellData =
    case cellData of
        AvAData { data } ->
            Tracked.isFailure data

        AverageData data ->
            Tracked.isFailure data

        DeviceBasedUsageData data ->
            Tracked.isFailure data


isCellDone : Cell -> Bool
isCellDone cell =
    case cell.data of
        AvAData { data, incompatibilities } ->
            Tracked.isDone data && Tracked.isDone incompatibilities

        AverageData data ->
            Tracked.isDone data

        DeviceBasedUsageData data ->
            Tracked.isDone data


isCellNotAsked : Cell -> Bool
isCellNotAsked cell =
    case cell.data of
        AvAData { data, incompatibilities } ->
            Tracked.isNotAsked data || Tracked.isNotAsked incompatibilities

        AverageData data ->
            Tracked.isNotAsked data

        DeviceBasedUsageData data ->
            Tracked.isNotAsked data


isIncompatibilityNotAsked : Cell -> Bool
isIncompatibilityNotAsked cell =
    case cell.data of
        AvAData { incompatibilities } ->
            Tracked.isNotAsked incompatibilities

        AverageData _ ->
            False

        DeviceBasedUsageData _ ->
            False


isFullyLoaded : AudienceCrosstab -> Bool
isFullyLoaded (AudienceCrosstab r) =
    Crosstab.all isCellDone r.crosstab
        && Dict.Any.all (\_ -> isCellDone) r.totals


isCellDataNotAsked : Cell -> Bool
isCellDataNotAsked cell =
    case cell.data of
        AvAData { data } ->
            Tracked.isNotAsked data

        AverageData data ->
            Tracked.isNotAsked data

        DeviceBasedUsageData data ->
            Tracked.isNotAsked data


isCellDataDone : Cell -> Bool
isCellDataDone cell =
    case cell.data of
        AvAData { data } ->
            Tracked.isDone data

        AverageData data ->
            Tracked.isDone data

        DeviceBasedUsageData data ->
            Tracked.isDone data


isIncompatibilitiesDone : Cell -> Bool
isIncompatibilitiesDone cell =
    case cell.data of
        AvAData { incompatibilities } ->
            Tracked.isDone incompatibilities

        AverageData _ ->
            True

        DeviceBasedUsageData _ ->
            True


isFullyLoadedCellData : AudienceCrosstab -> Bool
isFullyLoadedCellData (AudienceCrosstab r) =
    Crosstab.all isCellDataDone r.crosstab
        && Dict.Any.all (\_ -> isCellDataDone) r.totals


isLoading : AudienceCrosstab -> Bool
isLoading (AudienceCrosstab r) =
    let
        isCellLoading cell =
            case cell.data of
                AvAData { data, incompatibilities } ->
                    Tracked.isLoading data || Tracked.isLoading incompatibilities

                AverageData data ->
                    Tracked.isLoading data

                DeviceBasedUsageData data ->
                    Tracked.isLoading data
    in
    Crosstab.any isCellLoading r.crosstab
        || Dict.Any.any (\_ -> isCellLoading) r.totals


notDoneForColumnCount : AudienceItemId -> AudienceCrosstab -> Int
notDoneForColumnCount id (AudienceCrosstab r) =
    Crosstab.getValues r.crosstab
        |> Dict.Any.filter
            (\{ col } cell ->
                (AudienceItem.getId col.item == id)
                    && not (isCellDone cell)
            )
        |> Dict.Any.size


totalsNotDoneForColumnCount : AudienceCrosstab -> Int
totalsNotDoneForColumnCount (AudienceCrosstab r) =
    let
        crosstabColumns =
            Crosstab.getColumns r.crosstab
                |> List.map keyToComparable
                |> Set.fromList
    in
    Dict.Any.filter
        (\( item, _ ) cell ->
            Set.member (audienceItemToComparable item) crosstabColumns && not (isCellDone cell)
        )
        r.totals
        |> Dict.Any.size


notDoneForRowCount : AudienceItemId -> AudienceCrosstab -> Int
notDoneForRowCount id (AudienceCrosstab r) =
    Crosstab.getValues r.crosstab
        |> Dict.Any.filter
            (\{ row } cell ->
                (AudienceItem.getId row.item == id)
                    && not (isCellDone cell)
            )
        |> Dict.Any.size


totalsNotDoneForRowCount : AudienceCrosstab -> Int
totalsNotDoneForRowCount (AudienceCrosstab r) =
    let
        crosstabRows =
            Crosstab.getRows r.crosstab
                |> List.map keyToComparable
                |> Set.fromList
    in
    Dict.Any.filter
        (\( item, _ ) cell ->
            Set.member (audienceItemToComparable item) crosstabRows && not (isCellDone cell)
        )
        r.totals
        |> Dict.Any.size


isAnyNotAskedOrLoading : AudienceCrosstab -> Bool
isAnyNotAskedOrLoading (AudienceCrosstab r) =
    Crosstab.any (isCellDone >> not) r.crosstab
        || Dict.Any.any (\_ -> isCellDone >> not) r.totals


incrementIf : Bool -> Int -> Int
incrementIf cond n =
    if cond then
        n + 1

    else
        n


loadedCellDataCount : AudienceCrosstab -> Int
loadedCellDataCount (AudienceCrosstab r) =
    let
        count cell =
            case cell.data of
                AvAData { data } ->
                    incrementIf (Tracked.isDone data)

                AverageData data ->
                    incrementIf (Tracked.isDone data)

                DeviceBasedUsageData data ->
                    incrementIf (Tracked.isDone data)
    in
    Crosstab.foldr (\_ -> count) 0 r.crosstab
        + Dict.Any.foldr (\_ -> count) 0 r.totals


notLoadedCellDataCount : AudienceCrosstab -> Int
notLoadedCellDataCount (AudienceCrosstab r) =
    let
        count cell =
            incrementIf
                (not <| isCellDataDone cell)
    in
    Crosstab.foldr (\_ -> count) 0 r.crosstab
        + Dict.Any.foldr (\_ -> count) 0 r.totals


loadingCount : AudienceCrosstab -> Int
loadingCount (AudienceCrosstab r) =
    let
        count cell =
            case cell.data of
                AvAData { data, incompatibilities } ->
                    incrementIf (Tracked.isLoading data)
                        >> incrementIf (Tracked.isLoading incompatibilities)

                AverageData data ->
                    incrementIf (Tracked.isLoading data)

                DeviceBasedUsageData data ->
                    incrementIf (Tracked.isLoading data)
    in
    Crosstab.foldr (\_ -> count) 0 r.crosstab
        + Dict.Any.foldr (\_ -> count) 0 r.totals


{-| Function to generate TrackerId for possible cancellation of ongoing HTTP requests
-}
generateTrackerId : IdSet WaveCodeTag -> IdSet LocationCodeTag -> BaseAudience -> AudienceItem -> AudienceItem -> Tracked.TrackerId
generateTrackerId activeWaves activeLocations base item1 item2 =
    String.join "|"
        [ AudienceItem.getIdString item1 ++ "-" ++ AudienceItem.getIdString item2
        , "base:" ++ (AudienceItemId.toString <| BaseAudience.getId base)
        , "waves:" ++ String.join "," (List.map XB2.Share.Data.Id.unwrap <| Set.Any.toList activeWaves)
        , "locations:" ++ String.join "," (List.map XB2.Share.Data.Id.unwrap <| Set.Any.toList activeLocations)
        ]


{-| Function to generate TrackerId for possible cancellation of ongoing HTTP requests in
bulk API. Since the request can include several items, the result String is a hash of
the structure.
-}
generateBulkTrackerId :
    IdSet WaveCodeTag
    -> IdSet LocationCodeTag
    -> BaseAudience
    -> VisibleCells
    -> Tracked.TrackerId
generateBulkTrackerId activeWaves activeLocations base visibleCells =
    String.join "|"
        [ "base:" ++ (AudienceItemId.toString <| BaseAudience.getId base)
        , "waves:" ++ String.join "," (List.map XB2.Share.Data.Id.unwrap <| Set.Any.toList activeWaves)
        , "locations:" ++ String.join "," (List.map XB2.Share.Data.Id.unwrap <| Set.Any.toList activeLocations)
        , "visibleCells:"
            ++ (String.fromInt visibleCells.topLeftRow
                    ++ String.fromInt visibleCells.topLeftCol
                    ++ String.fromInt visibleCells.bottomRightRow
                    ++ String.fromInt visibleCells.bottomRightCol
                    ++ String.fromInt visibleCells.frozenRows
                    ++ String.fromInt visibleCells.frozenCols
               )
        ]


{-| HeatmapBehaviour decides which parts of the crosstab:

  - are used in the min,max range calculations (used for heatmap)
  - are coloured when using heatmap

Naming of the crosstab parts:

    +----------------+-------------------+
    | total vs total | column totals ... |
    +----------------+-------------------+
    | row totals     | data cells        |
    | .              |            .      |
    | .              |              .    |
    | .              |                .  |
    +----------------+-------------------+

-}
type HeatmapBehaviour
    = AllCells
    | AllExceptRowTotals
    | AllExceptColumnTotals
    | DataCellsOnly


heatmapBehaviour : Metric -> HeatmapBehaviour
heatmapBehaviour metric =
    case metric of
        Index ->
            DataCellsOnly

        RowPercentage ->
            AllExceptRowTotals

        ColumnPercentage ->
            AllExceptColumnTotals

        -- These are currently unused:
        Size ->
            AllCells

        Sample ->
            AllCells


getAvAData : CellData -> Maybe IntersectResult
getAvAData cellData =
    case cellData of
        AverageData _ ->
            Nothing

        DeviceBasedUsageData _ ->
            Nothing

        AvAData result ->
            Tracked.toMaybe result.data


getAverageData : CellData -> Maybe AverageResult
getAverageData cellData =
    case cellData of
        AverageData result ->
            Tracked.toMaybe result

        DeviceBasedUsageData _ ->
            Nothing

        AvAData _ ->
            Nothing


getDeviceBasedUsageData : CellData -> Maybe DeviceBasedUsageResult
getDeviceBasedUsageData cellData =
    case cellData of
        DeviceBasedUsageData result ->
            Tracked.toMaybe result

        AverageData _ ->
            Nothing

        AvAData _ ->
            Nothing


{-| Filter out Index=0. This is mainly useful for Heatmap.
-}
getFilteredMetricValue : Metric -> CellData -> Maybe Float
getFilteredMetricValue metric cellData =
    getAvAData cellData
        |> Maybe.map (AudienceIntersect.getValue metric)
        |> Maybe.filter (\value_ -> metric /= Index || value_ > 0)


{-| Gets the range _for the current base_
-}
getRange : Metric -> AudienceCrosstab -> Range
getRange metric (AudienceCrosstab { crosstab, totals, bases }) =
    let
        base =
            Zipper.current bases |> unwrapCrosstabBase

        cellToMetricValue : Cell -> Maybe Float
        cellToMetricValue =
            .data >> getFilteredMetricValue metric

        dataCells : Range
        dataCells =
            Crosstab.getRange cellToMetricValue base crosstab

        rowTotals : Range
        rowTotals =
            {- BEWARE: row totals mean the totals OF the rows,
               meaning the totals in the totals COLUMN (the thing on the left)!
            -}
            crosstab
                |> Crosstab.getRows
                |> List.filterMap
                    (\key ->
                        Dict.Any.get ( key.item, base ) totals
                            |> Maybe.andThen cellToMetricValue
                    )
                |> Range.fromList

        columnTotals : Range
        columnTotals =
            {- BEWARE: column totals mean the totals OF the columns,
               meaning the totals in the totals ROW (the thing at the top)!
            -}
            crosstab
                |> Crosstab.getColumns
                |> List.filterMap
                    (\key ->
                        Dict.Any.get ( key.item, base ) totals
                            |> Maybe.andThen cellToMetricValue
                    )
                |> Range.fromList
    in
    case heatmapBehaviour metric of
        AllCells ->
            let
                totalVsTotal : Range
                totalVsTotal =
                    Dict.Any.get ( AudienceItem.totalItem, base ) totals
                        |> Maybe.andThen cellToMetricValue
                        |> Maybe.map Range.fromNumber
                        |> Maybe.withDefault Range.init
            in
            List.foldl Range.combine
                dataCells
                [ rowTotals
                , columnTotals
                , totalVsTotal
                ]

        AllExceptRowTotals ->
            Range.combine dataCells columnTotals

        AllExceptColumnTotals ->
            Range.combine dataCells rowTotals

        DataCellsOnly ->
            dataCells


getLimitForBasesCount : { limit : Int, basesCount : Int } -> Int
getLimitForBasesCount { limit, basesCount } =
    limit // basesCount


getCurrentLimit : AudienceCrosstab -> Int
getCurrentLimit (AudienceCrosstab { bases, limit }) =
    getLimitForBasesCount
        { limit = limit
        , basesCount = Zipper.length bases
        }


{-| Don't do the operation if it would exceed the cells limit.
{ addedCols , addedRows } = without totals included
-}
ifNotExceedingLimit : { addedCols : Int, addedRows : Int } -> (CrosstabTable -> CrosstabTable) -> AudienceCrosstab -> Result ErrorAddingRowOrColumn AudienceCrosstab
ifNotExceedingLimit { addedCols, addedRows } fn crosstab =
    let
        { rowCount, colCount } =
            getDimensionsWithTotals crosstab

        newSize =
            (rowCount + addedRows) * (colCount + addedCols)

        limit =
            getCurrentLimit crosstab
    in
    if newSize > limit then
        Err
            { exceedingSize = newSize
            , sizeLimit = limit
            , currentBasesCount = getBaseAudiencesCount crosstab
            }

    else
        Ok <| updateCrosstab fn crosstab


unwrapCrosstabBase : CrosstabBaseAudience -> BaseAudience
unwrapCrosstabBase crosstabBase =
    case crosstabBase of
        DefaultBase base ->
            base

        SelectableBase { base } ->
            base


basesToList : Zipper CrosstabBaseAudience -> List BaseAudience
basesToList =
    List.map unwrapCrosstabBase << Zipper.toList


addRow : CellData -> Key -> AudienceCrosstab -> Result ErrorAddingRowOrColumn AudienceCrosstab
addRow cellData headerValue ((AudienceCrosstab r) as crosstab) =
    ifNotExceedingLimit { addedCols = 0, addedRows = 1 }
        (Crosstab.addRow { emptyCell | data = cellData } headerValue (basesToList r.bases))
        crosstab


addRows : MultipleAudiencesInserter
addRows data ((AudienceCrosstab r) as crosstab) =
    let
        dataToAdd : List { value : Cell, key : Key }
        dataToAdd =
            List.map (\d -> { value = { emptyCell | data = d.value }, key = d.key }) data
    in
    ifNotExceedingLimit { addedCols = 0, addedRows = List.length data }
        (Crosstab.addRows dataToAdd (basesToList r.bases))
        crosstab


addRowsAtIndex : Int -> MultipleAudiencesInserter
addRowsAtIndex index data ((AudienceCrosstab r) as crosstab) =
    ifNotExceedingLimit { addedCols = 0, addedRows = List.length data }
        (\xtabs ->
            List.foldr
                (\row ->
                    Crosstab.addRowAtIndex
                        { emptyCell | data = row.value }
                        index
                        row.key
                        (basesToList r.bases)
                )
                xtabs
                data
        )
        crosstab


addColumn : CellData -> Key -> AudienceCrosstab -> Result ErrorAddingRowOrColumn AudienceCrosstab
addColumn cellData headerValue ((AudienceCrosstab r) as crosstab) =
    ifNotExceedingLimit { addedCols = 1, addedRows = 0 }
        (Crosstab.addColumn { emptyCell | data = cellData } headerValue (basesToList r.bases))
        crosstab


addColumnsAtIndex : Int -> MultipleAudiencesInserter
addColumnsAtIndex index data ((AudienceCrosstab r) as crosstab) =
    ifNotExceedingLimit { addedCols = List.length data, addedRows = 0 }
        (\xtabs ->
            List.foldr
                (\col ->
                    Crosstab.addColumnAtIndex
                        { emptyCell | data = col.value }
                        index
                        col.key
                        (basesToList r.bases)
                )
                xtabs
                data
        )
        crosstab


addColumns : MultipleAudiencesInserter
addColumns data ((AudienceCrosstab r) as crosstab) =
    let
        dataToAdd : List { value : Cell, key : Key }
        dataToAdd =
            List.map (\d -> { value = { emptyCell | data = d.value }, key = d.key }) data
    in
    ifNotExceedingLimit { addedCols = List.length data, addedRows = 0 }
        (Crosstab.addColumns dataToAdd (basesToList r.bases))
        crosstab


maybeValue : { r | row : Key, col : Key, base : BaseAudience } -> AudienceCrosstab -> Maybe Cell
maybeValue cell (AudienceCrosstab { crosstab, totals }) =
    crosstab
        |> Crosstab.value
            { row = cell.row
            , col = cell.col
            , base = cell.base
            }
        |> Maybe.orElseLazy
            (\() ->
                let
                    otherItem =
                        if AudienceItem.getId cell.row.item == AudienceItemId.total then
                            cell.col

                        else
                            cell.row
                in
                Dict.Any.get ( otherItem.item, cell.base ) totals
            )


value : { r | row : Key, col : Key, base : BaseAudience } -> AudienceCrosstab -> Cell
value cell ac =
    maybeValue cell ac
        |> Maybe.withDefault emptyCell


valueForAudienceItem : { row : AudienceItem, col : AudienceItem, base : BaseAudience } -> AudienceCrosstab -> Cell
valueForAudienceItem { row, col, base } ac =
    let
        {- No need to care about isSelected because of current keyToComparable implementation -}
        key =
            { row =
                { item = row
                , isSelected = False
                }
            , col =
                { item = col
                , isSelected = False
                }
            , base = base
            }
    in
    value key ac


setSortCellsForLoading : Sort -> AudienceCrosstab -> AudienceCrosstab
setSortCellsForLoading { rows, columns } crosstab =
    crosstab
        |> (case XB2.Sort.sortingAudience columns of
                Just id ->
                    setRowShouldBeLoaded id

                Nothing ->
                    identity
           )
        |> (case XB2.Sort.sortingAudience rows of
                Just id ->
                    setColumnShouldBeLoaded id

                Nothing ->
                    identity
           )


goToBaseAtIndex :
    Int
    -> Sort
    -> AudienceCrosstab
    -> Maybe ( AudienceCrosstab, List Command )
goToBaseAtIndex index sort (AudienceCrosstab audienceCrosstab) =
    let
        targetBase : Maybe (Zipper CrosstabBaseAudience)
        targetBase =
            audienceCrosstab.bases
                |> Zipper.goToIndex index
    in
    targetBase
        |> Maybe.map
            (\newBases ->
                AudienceCrosstab { audienceCrosstab | bases = newBases }
                    |> setCellsVisibility True audienceCrosstab.visibleCells
                    |> setSortCellsForLoading sort
                    |> reloadNotLoadedCells
            )


setFocusToBase : BaseAudience -> AudienceCrosstab -> AudienceCrosstab
setFocusToBase base (AudienceCrosstab audienceCrosstab) =
    AudienceCrosstab
        { audienceCrosstab
            | bases =
                Zipper.focus (unwrapCrosstabBase >> (==) base) audienceCrosstab.bases
                    |> Maybe.withDefault audienceCrosstab.bases
        }



-- CONSTANTS


{-| The limit holds for the sum of all _non-total_ cells across all bases
-}
crosstabSizeLimit : Can -> Int
crosstabSizeLimit can =
    if can XB2.Share.Permissions.UseXB50kTableLimit then
        50000

    else
        10000


{-| This limit is for determine when return real visibleCells or faked with full table range.
Small tables don't need partial (lazy) render
-}
limitForFullRender : Int
limitForFullRender =
    30


getKeyMapping : AudienceCrosstab -> AnyDict AudienceItemId.ComparableId AudienceItemId Key
getKeyMapping (AudienceCrosstab { keyMapping }) =
    keyMapping


computeKeyMapping : CrosstabTable -> AnyDict AudienceItemId.ComparableId AudienceItemId Key
computeKeyMapping crosstab =
    (Crosstab.getRows crosstab ++ Crosstab.getColumns crosstab)
        |> List.map (\key -> ( AudienceItem.getId key.item, key ))
        |> Dict.Any.fromList AudienceItemId.toComparable


updateKeyItem : (AudienceItem -> AudienceItem) -> Key -> Key
updateKeyItem fn key =
    { key | item = fn key.item }


type OriginalOrder
    = NotSet
    | OriginalOrder (List Key)


mapOrder : (AudienceItem -> AudienceItem) -> OriginalOrder -> OriginalOrder
mapOrder fn order =
    case order of
        NotSet ->
            NotSet

        OriginalOrder keys ->
            OriginalOrder <| List.map (updateKeyItem fn) keys


questionCodes : AudienceCrosstab -> List NamespaceAndQuestionCode
questionCodes crosstab =
    let
        rows : List Key
        rows =
            getRows crosstab

        columns : List Key
        columns =
            getColumns crosstab
    in
    (rows ++ columns)
        |> List.fastConcatMap (.item >> AudienceItem.getDefinition >> XB2.Data.definitionNamespaceAndQuestionCodes)
        |> XB2.Share.Data.Id.setFromList
        |> Set.Any.toList


questionCodesWithBases : AudienceCrosstab -> List NamespaceAndQuestionCode
questionCodesWithBases crosstab =
    let
        rows : List Key
        rows =
            getRows crosstab

        columns : List Key
        columns =
            getColumns crosstab

        baseAudiences : List NamespaceAndQuestionCode
        baseAudiences =
            getBaseAudiences crosstab
                |> Zipper.toList
                |> List.map BaseAudience.getExpression
                |> List.fastConcatMap XB2.Data.Audience.Expression.getQuestionCodes
    in
    (rows ++ columns)
        |> List.fastConcatMap (.item >> AudienceItem.getDefinition >> XB2.Data.definitionNamespaceAndQuestionCodes)
        |> List.append baseAudiences
        |> XB2.Share.Data.Id.setFromList
        |> Set.Any.toList


namespaceCodesWithBases : AudienceCrosstab -> List Namespace.Code
namespaceCodesWithBases crosstab =
    let
        rows : List Key
        rows =
            getRows crosstab

        columns : List Key
        columns =
            getColumns crosstab

        baseAudiencesNamespaceCodes : List Namespace.Code
        baseAudiencesNamespaceCodes =
            getBaseAudiences crosstab
                |> Zipper.toList
                |> List.fastConcatMap BaseAudience.namespaceCodes

        namespaceCodesSet : Set.Any.AnySet Namespace.StringifiedCode Namespace.Code
        namespaceCodesSet =
            (rows ++ columns)
                |> List.fastConcatMap keyNamespaceCodes
                |> Set.Any.fromList Namespace.codeToString
    in
    baseAudiencesNamespaceCodes
        |> List.foldr Set.Any.insert namespaceCodesSet
        |> Set.Any.toList


namespaceCodes : AudienceCrosstab -> List Namespace.Code
namespaceCodes crosstab =
    (getRows crosstab ++ getColumns crosstab)
        |> List.fastConcatMap keyNamespaceCodes
        |> List.unique


keyNamespaceCodes : Key -> List Namespace.Code
keyNamespaceCodes key =
    key.item
        |> AudienceItem.getDefinition
        |> XB2.Data.definitionNamespaceCodes
