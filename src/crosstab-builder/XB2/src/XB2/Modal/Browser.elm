module XB2.Modal.Browser exposing
    ( AffixingOrEditingItems(..)
    , Config
    , DnDModel
    , ModalTab
    , Model
    , Msg
    , SelectedItem(..)
    , SelectedItems
    , SelectedItemsGroup(..)
    , Warning(..)
    , WarningState
    , addBaseView
    , addToTableView
    , affixBaseView
    , affixTableView
    , arePossibleDatasetIncompatibilities
    , editBaseView
    , editTableView
    , expressionToSelectedItem
    , getCaptionFromGroup
    , getExpressionFromGroup
    , getModalWarning
    , getSelectedItemQuestionCodes
    , groupFoldr
    , init
    , isSelectedAverage
    , metadataNotesView
    , replaceDefaultBaseView
    , selectedItemNamespaceCodes
    , setModalBrowserWarning
    , subscriptions
    , update
    )

{-| Module that handles all the logic related to the WebComponents' modals.

TODO: This really needs a rework, it is too big and obscure to read.

-}

import Basics.Extra exposing (flip)
import BiDict.Assoc exposing (BiDict)
import Browser.Dom as Dom
import Browser.Events
import Cmd.Extra as Cmd
import Dict.Any
import Html exposing (Html)
import Html.Attributes as Attrs
import Html.Events as Events
import Html.Extra as Html
import Html.Lazy
import Json.Decode as Decode
import List.Extra as List
import List.NonEmpty as NonemptyList exposing (NonEmpty)
import Maybe.Extra as Maybe
import RemoteData exposing (RemoteData(..), WebData)
import Set.Any
import Task
import Time
import WeakCss exposing (ClassName)
import XB2.Analytics as Analytics
import XB2.Data exposing (AudienceDefinition, XBUserSettings)
import XB2.Data.Audience as Audience
import XB2.Data.Audience.Expression as Expression
import XB2.Data.Audience.Flag as AudienceFlag
import XB2.Data.Audience.Folder as AudienceFolder
import XB2.Data.AudienceCrosstab as ACrosstab exposing (AudienceCrosstab, Direction(..))
import XB2.Data.AudienceItem
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Namespace as Namespace
import XB2.Data.UndoEvent as UndoEvent
import XB2.Data.Zod.Optional as Optional
import XB2.Modal.GroupingPanel as XB2GroupingPanel
import XB2.Router exposing (Route)
import XB2.Share.Analytics.Place as Place
import XB2.Share.Config exposing (Flags)
import XB2.Share.Data.Id exposing (IdDict, IdSet)
import XB2.Share.Data.Labels
    exposing
        ( Location
        , LocationCodeTag
        , NamespaceAndQuestionCode
        , NamespaceAndQuestionCodeTag
        , NamespaceLineage
        , QuestionV2
        , Wave
        , WaveCodeTag
        )
import XB2.Share.Data.Platform2
    exposing
        ( Attribute
        , Dataset
        , DatasetCode
        , DatasetCodeTag
        )
import XB2.Share.DragAndDrop.Move
import XB2.Share.Gwi.List as List
import XB2.Share.Icons
import XB2.Share.Icons.Platform2 as P2Icons
import XB2.Share.Platform2.AudienceBrowser as AudienceBrowser
import XB2.Share.Platform2.Dropdown.DropdownMenu as DropdownMenu exposing (DropdownMenu)
import XB2.Share.Platform2.Dropdown.Item as DropdownItem
import XB2.Share.Platform2.Grouping exposing (Grouping(..))
import XB2.Share.Platform2.GroupingPanel as GroupingPanel
import XB2.Share.Platform2.Modal as P2Modals
import XB2.Share.Plural
import XB2.Share.Spinner
import XB2.Share.UndoRedo as UndoRedo
import XB2.Store exposing (Store)
import XB2.Utils.Set.Any as AnySet
import XB2.Views.AttributeBrowser as AttributeBrowser exposing (Average(..))


type alias Config msg =
    { addItemsToTable : Direction -> Grouping -> SelectedItems -> msg
    , viewAffixModalFromAttrBrowser : Expression.LogicOperator -> Grouping -> Analytics.AffixedFrom -> SelectedItems -> msg
    , viewEditModalFromAttrBrowser : Grouping -> SelectedItems -> msg
    , addBaseAudiences : Grouping -> SelectedItems -> msg
    , replaceDefaultBase : Grouping -> SelectedItems -> msg
    , msg : Msg -> msg
    , noOp : msg
    , closeModal : msg
    , createAudience : msg
    , editAudience : Audience.Id -> msg
    , itemToggled : SelectedItem -> SelectedItems -> msg
    , updateUserSettings : XBUserSettings -> msg
    , gotAttributeBrowserStateSnapshot : Decode.Value -> msg
    }


type SelectedItemsGroup
    = ItemsGroup Grouping (Maybe String) (NonEmpty SelectedItemsGroup)
    | SingleAttribute Attribute
    | SingleAudience Audience.Audience


type SelectedItem
    = SelectedAttribute Attribute
    | SelectedAudience Audience.Audience
    | SelectedAverage AttributeBrowser.Average
    | SelectedGroup SelectedItemsGroup


logicOperatorToGrouping : Expression.LogicOperator -> Grouping
logicOperatorToGrouping logicOperator =
    case logicOperator of
        Expression.And ->
            And

        Expression.Or ->
            Or


expressionToSelectedItem : { maybeFirstGroupTitle : Maybe String, questions : IdDict NamespaceAndQuestionCodeTag (WebData QuestionV2) } -> Expression.Expression -> SelectedItem
expressionToSelectedItem options expression =
    case expression of
        Expression.FirstLevelLeaf leafData ->
            let
                possibleDatapointCodeAndSuffixCodeCombinations : NonEmpty ( XB2.Share.Data.Labels.QuestionAndDatapointCode, Maybe XB2.Share.Data.Labels.SuffixCode )
                possibleDatapointCodeAndSuffixCodeCombinations =
                    case leafData.suffixCodes of
                        Optional.Present suffixCodes ->
                            NonemptyList.concatMap
                                (\suffixCode ->
                                    NonemptyList.map
                                        (\questionAndDatapointCode ->
                                            ( questionAndDatapointCode, Just suffixCode )
                                        )
                                        leafData.questionAndDatapointCodes
                                )
                                suffixCodes

                        Optional.Undefined ->
                            NonemptyList.map (\questionAndDatapointCode -> ( questionAndDatapointCode, Nothing )) leafData.questionAndDatapointCodes
            in
            case possibleDatapointCodeAndSuffixCodeCombinations of
                ( ( questionAndDatapointCode, maybeSuffixCode ), [] ) ->
                    let
                        ( namespaceCode, questionCode ) =
                            XB2.Share.Data.Labels.splitQuestionCode leafData.namespaceAndQuestionCode

                        ( _, datapointCode ) =
                            XB2.Share.Data.Labels.splitQuestionAndDatapointCodeCheckingWavesQuestion questionAndDatapointCode questionCode

                        questionName =
                            options.questions
                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                |> Maybe.andThen RemoteData.toMaybe
                                |> Maybe.map .fullName
                                |> Maybe.withDefault (XB2.Share.Data.Id.unwrap questionCode)

                        datapointName =
                            options.questions
                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                |> Maybe.andThen RemoteData.toMaybe
                                |> Maybe.map .datapoints
                                |> Maybe.andThen (NonemptyList.find (\dp -> dp.code == questionAndDatapointCode))
                                |> Maybe.map .name
                                |> Maybe.withDefault (XB2.Share.Data.Id.unwrap questionAndDatapointCode)

                        suffixName =
                            options.questions
                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                |> Maybe.andThen RemoteData.toMaybe
                                |> Maybe.andThen .suffixes
                                |> Maybe.andThen (NonemptyList.find (\s -> Just s.code == maybeSuffixCode))
                                |> Maybe.map .name

                        questionDescription =
                            options.questions
                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                |> Maybe.andThen RemoteData.toMaybe
                                |> Maybe.map .name
                    in
                    SelectedAttribute
                        { namespaceCode = namespaceCode
                        , codes =
                            { datapointCode = datapointCode
                            , questionCode = questionCode
                            , suffixCode = maybeSuffixCode
                            }
                        , questionName = questionName
                        , datapointName = datapointName
                        , suffixName = suffixName
                        , questionDescription = questionDescription

                        -- Maybe this fields are not necessary?
                        , order = 0
                        , compatibilitiesMetadata = Nothing
                        , taxonomyPaths = Nothing
                        , isExcluded = Maybe.withDefault False (Optional.toMaybe leafData.isExcluded)
                        }

                questionAndDatapointCodesAndMaybeSuffixCodes ->
                    SelectedGroup <|
                        ItemsGroup Or
                            options.maybeFirstGroupTitle
                            (NonemptyList.map
                                (\( questionAndDatapointCode, maybeSuffixCode ) ->
                                    let
                                        ( namespaceCode, questionCode ) =
                                            XB2.Share.Data.Labels.splitQuestionCode leafData.namespaceAndQuestionCode

                                        ( _, datapointCode ) =
                                            XB2.Share.Data.Labels.splitQuestionAndDatapointCodeCheckingWavesQuestion questionAndDatapointCode questionCode

                                        questionName =
                                            options.questions
                                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                                |> Maybe.andThen RemoteData.toMaybe
                                                |> Maybe.map .fullName
                                                |> Maybe.withDefault (XB2.Share.Data.Id.unwrap questionCode)

                                        datapointName =
                                            options.questions
                                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                                |> Maybe.andThen RemoteData.toMaybe
                                                |> Maybe.map .datapoints
                                                |> Maybe.andThen (NonemptyList.find (\dp -> dp.code == questionAndDatapointCode))
                                                |> Maybe.map .name
                                                |> Maybe.withDefault (XB2.Share.Data.Id.unwrap questionAndDatapointCode)

                                        suffixName =
                                            options.questions
                                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                                |> Maybe.andThen RemoteData.toMaybe
                                                |> Maybe.andThen .suffixes
                                                |> Maybe.andThen (NonemptyList.find (\s -> Just s.code == maybeSuffixCode))
                                                |> Maybe.map .name

                                        questionDescription =
                                            options.questions
                                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                                |> Maybe.andThen RemoteData.toMaybe
                                                |> Maybe.map .name
                                    in
                                    SingleAttribute
                                        { namespaceCode = namespaceCode
                                        , codes =
                                            { datapointCode = datapointCode
                                            , questionCode = questionCode
                                            , suffixCode = maybeSuffixCode
                                            }
                                        , questionName = questionName
                                        , datapointName = datapointName
                                        , suffixName = suffixName
                                        , questionDescription = questionDescription
                                        , order = 0
                                        , compatibilitiesMetadata = Nothing
                                        , taxonomyPaths = Nothing
                                        , isExcluded = Maybe.withDefault False (Optional.toMaybe leafData.isExcluded)
                                        }
                                )
                                questionAndDatapointCodesAndMaybeSuffixCodes
                            )

        Expression.FirstLevelNode operator subExprs ->
            SelectedGroup (ItemsGroup (logicOperatorToGrouping operator) options.maybeFirstGroupTitle (NonemptyList.map (expressionHelpToSelectedItemsGroup options) subExprs))

        Expression.AllRespondents ->
            let
                ( namespaceCode, questionCode ) =
                    XB2.Share.Data.Labels.splitQuestionCode Expression.allInternetUsersLeafData.namespaceAndQuestionCode

                ( _, datapointCode ) =
                    XB2.Share.Data.Labels.splitQuestionAndDatapointCodeCheckingWavesQuestion (NonemptyList.head Expression.allInternetUsersLeafData.questionAndDatapointCodes) questionCode
            in
            SelectedAttribute
                { namespaceCode = namespaceCode
                , codes =
                    { datapointCode = datapointCode
                    , questionCode = questionCode
                    , suffixCode = Nothing
                    }
                , questionName = Audience.defaultName
                , datapointName = Audience.defaultName
                , suffixName = Nothing
                , questionDescription = Just Audience.defaultName
                , order = 1
                , compatibilitiesMetadata = Nothing
                , taxonomyPaths = Nothing
                , isExcluded = False
                }


expressionHelpToSelectedItemsGroup : { maybeFirstGroupTitle : Maybe String, questions : IdDict NamespaceAndQuestionCodeTag (WebData QuestionV2) } -> Expression.ExpressionHelp -> SelectedItemsGroup
expressionHelpToSelectedItemsGroup options expressionHelp =
    case expressionHelp of
        Expression.Leaf leafData ->
            let
                possibleDatapointCodeAndSuffixCodeCombinations : NonEmpty ( XB2.Share.Data.Labels.QuestionAndDatapointCode, Maybe XB2.Share.Data.Labels.SuffixCode )
                possibleDatapointCodeAndSuffixCodeCombinations =
                    case leafData.suffixCodes of
                        Optional.Present suffixCodes ->
                            NonemptyList.concatMap
                                (\suffixCode ->
                                    NonemptyList.map
                                        (\questionAndDatapointCode ->
                                            ( questionAndDatapointCode, Just suffixCode )
                                        )
                                        leafData.questionAndDatapointCodes
                                )
                                suffixCodes

                        Optional.Undefined ->
                            NonemptyList.map (\questionAndDatapointCode -> ( questionAndDatapointCode, Nothing )) leafData.questionAndDatapointCodes
            in
            case possibleDatapointCodeAndSuffixCodeCombinations of
                ( ( questionAndDatapointCode, maybeSuffixCode ), [] ) ->
                    let
                        ( namespaceCode, questionCode ) =
                            XB2.Share.Data.Labels.splitQuestionCode leafData.namespaceAndQuestionCode

                        ( _, datapointCode ) =
                            XB2.Share.Data.Labels.splitQuestionAndDatapointCodeCheckingWavesQuestion questionAndDatapointCode questionCode

                        questionName =
                            options.questions
                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                |> Maybe.andThen RemoteData.toMaybe
                                |> Maybe.map .fullName
                                |> Maybe.withDefault (XB2.Share.Data.Id.unwrap questionCode)

                        datapointName =
                            options.questions
                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                |> Maybe.andThen RemoteData.toMaybe
                                |> Maybe.map .datapoints
                                |> Maybe.andThen (NonemptyList.find (\dp -> dp.code == questionAndDatapointCode))
                                |> Maybe.map .name
                                |> Maybe.withDefault (XB2.Share.Data.Id.unwrap questionAndDatapointCode)

                        suffixName =
                            options.questions
                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                |> Maybe.andThen RemoteData.toMaybe
                                |> Maybe.andThen .suffixes
                                |> Maybe.andThen (NonemptyList.find (\s -> Just s.code == maybeSuffixCode))
                                |> Maybe.map .name

                        questionDescription =
                            options.questions
                                |> Dict.Any.get leafData.namespaceAndQuestionCode
                                |> Maybe.andThen RemoteData.toMaybe
                                |> Maybe.map .name
                    in
                    SingleAttribute
                        { namespaceCode = namespaceCode
                        , codes =
                            { datapointCode = datapointCode
                            , questionCode = questionCode
                            , suffixCode = maybeSuffixCode
                            }
                        , questionName = questionName
                        , datapointName = datapointName
                        , suffixName = suffixName
                        , questionDescription = questionDescription
                        , order = 0
                        , compatibilitiesMetadata = Nothing
                        , taxonomyPaths = Nothing
                        , isExcluded = Maybe.withDefault False (Optional.toMaybe leafData.isExcluded)
                        }

                questionAndDatapointCodesAndMaybeSuffixCodes ->
                    ItemsGroup Or
                        Nothing
                        (NonemptyList.map
                            (\( questionAndDatapointCode, maybeSuffixCode ) ->
                                let
                                    ( namespaceCode, questionCode ) =
                                        XB2.Share.Data.Labels.splitQuestionCode leafData.namespaceAndQuestionCode

                                    ( _, datapointCode ) =
                                        XB2.Share.Data.Labels.splitQuestionAndDatapointCodeCheckingWavesQuestion questionAndDatapointCode questionCode

                                    questionName =
                                        options.questions
                                            |> Dict.Any.get leafData.namespaceAndQuestionCode
                                            |> Maybe.andThen RemoteData.toMaybe
                                            |> Maybe.map .fullName
                                            |> Maybe.withDefault (XB2.Share.Data.Id.unwrap questionCode)

                                    datapointName =
                                        options.questions
                                            |> Dict.Any.get leafData.namespaceAndQuestionCode
                                            |> Maybe.andThen RemoteData.toMaybe
                                            |> Maybe.map .datapoints
                                            |> Maybe.andThen (NonemptyList.find (\dp -> dp.code == questionAndDatapointCode))
                                            |> Maybe.map .name
                                            |> Maybe.withDefault (XB2.Share.Data.Id.unwrap questionAndDatapointCode)

                                    suffixName =
                                        options.questions
                                            |> Dict.Any.get leafData.namespaceAndQuestionCode
                                            |> Maybe.andThen RemoteData.toMaybe
                                            |> Maybe.andThen .suffixes
                                            |> Maybe.andThen (NonemptyList.find (\s -> Just s.code == maybeSuffixCode))
                                            |> Maybe.map .name

                                    questionDescription =
                                        options.questions
                                            |> Dict.Any.get leafData.namespaceAndQuestionCode
                                            |> Maybe.andThen RemoteData.toMaybe
                                            |> Maybe.map .name
                                in
                                SingleAttribute
                                    { namespaceCode = namespaceCode
                                    , codes =
                                        { datapointCode = datapointCode
                                        , questionCode = questionCode
                                        , suffixCode = maybeSuffixCode
                                        }
                                    , questionName = questionName
                                    , datapointName = datapointName
                                    , suffixName = suffixName
                                    , questionDescription = questionDescription
                                    , order = 0
                                    , compatibilitiesMetadata = Nothing
                                    , taxonomyPaths = Nothing
                                    , isExcluded = Maybe.withDefault False (Optional.toMaybe leafData.isExcluded)
                                    }
                            )
                            questionAndDatapointCodesAndMaybeSuffixCodes
                        )

        Expression.Node operator subExprs ->
            ItemsGroup (logicOperatorToGrouping operator) Nothing (NonemptyList.map (expressionHelpToSelectedItemsGroup options) subExprs)


type alias DnDSystem =
    XB2.Share.DragAndDrop.Move.System Msg (GroupingPanel.Item SelectedItem) (GroupingPanel.Item SelectedItem)


type alias DnDModel =
    XB2.Share.DragAndDrop.Move.Model (GroupingPanel.Item SelectedItem) (GroupingPanel.Item SelectedItem)


dndSystem : DnDSystem
dndSystem =
    XB2.Share.DragAndDrop.Move.config
        |> XB2.Share.DragAndDrop.Move.withContainer XB2GroupingPanel.itemsElementId
        |> XB2.Share.DragAndDrop.Move.withOffset { top = 0, right = 30, bottom = 10, left = 0 }
        |> XB2.Share.DragAndDrop.Move.ghostStyle [ XB2.Share.DragAndDrop.Move.preserveWidth ]
        |> XB2.Share.DragAndDrop.Move.create DragAndDropMsg


type alias SelectedItems =
    List SelectedItem


type AffixingOrEditingItems
    = NotAffixingOrEditing
    | AffixingBases (NonEmpty BaseAudience)
    | AffixingRowsOrColumns (NonEmpty ( Direction, ACrosstab.Key ))
    | EditingBases (NonEmpty BaseAudience)
    | EditingRowsOrColumns (NonEmpty ( Direction, ACrosstab.Key ))


type Warning
    = PossibleIncompatibilities
    | ClickedDisabledAudience


type WarningState
    = NoWarning
    | WarningVisible { msTTL : Int, warning : Warning }


warningVisiblityTime : Int
warningVisiblityTime =
    5000


type alias StateForGroupingPanel msg =
    { clearAllMsg : msg
    , clearItemMsg : SelectedItem -> msg
    , groupingSelectedMsg : Grouping -> msg
    , isAffixing : Bool
    , activeGrouping : Grouping
    , originalItemsBeforeEditing : SelectedItems
    , items : SelectedItems
    , selectedBasesCount : Int
    , warning : WarningState
    , affixedFrom : Analytics.AffixedFrom
    , attributesLoading : Bool
    , model : Model
    , undoMsg : msg
    , redoMsg : msg
    , canUndo : Bool
    , canRedo : Bool
    }


type ModalTab
    = AttributesTab
    | AudiencesTab


type alias Model =
    UndoRedo.UndoRedo
        UndoEvent.UndoEvent
        { activeWaves : IdSet WaveCodeTag
        , activeLocations : IdSet LocationCodeTag
        , activeTab : ModalTab
        , selectedItems : SelectedItems
        , originalSelectedItemsBeforeEditing : SelectedItems
        , activeGrouping : Grouping
        , errorMessage : Maybe String
        , incompatibilityWarningNote : Maybe AttributeBrowser.WarningNote
        , groupingPanelWarning : WarningState
        , attributeBrowserLoadingAttributes : Bool
        , activeDropdown : Maybe (DropdownMenu.DropdownMenu Msg)
        , groupingItemWith : Maybe ( List SelectedItem, SelectedItem )
        , dnd : DnDModel
        , renamingItems : SelectedItems
        }


selectedItemsGroupToString : SelectedItemsGroup -> String
selectedItemsGroupToString itemsGroup =
    case itemsGroup of
        SingleAttribute attr ->
            "attr--" ++ XB2.Share.Data.Platform2.attributeToString attr

        SingleAudience audience ->
            "audience--" ++ Audience.idToString audience.id

        ItemsGroup _ _ subnodes ->
            NonemptyList.foldr (\group acc -> acc ++ selectedItemsGroupToString group) "group--" subnodes


selectedItemToString : SelectedItem -> String
selectedItemToString item =
    case item of
        SelectedAverage avg ->
            [ AttributeBrowser.getAverageQuestionCode avg |> XB2.Share.Data.Id.unwrap
            , AttributeBrowser.getAverageDatapointCode avg
                |> Maybe.unwrap "" XB2.Share.Data.Id.unwrap
            ]
                |> String.join "__"
                |> (++) "average__"

        SelectedAudience a ->
            "audience---" ++ Audience.idToString a.id

        SelectedAttribute attr ->
            "attribute--" ++ XB2.Share.Data.Platform2.attributeToString attr

        SelectedGroup group ->
            selectedItemsGroupToString group
                |> (++) "group--"


isSelectedAverage : SelectedItem -> Bool
isSelectedAverage item =
    case item of
        SelectedAverage _ ->
            True

        SelectedAudience _ ->
            False

        SelectedAttribute _ ->
            False

        SelectedGroup _ ->
            False


isSelectedGroup : SelectedItem -> Bool
isSelectedGroup item =
    case item of
        SelectedAverage _ ->
            False

        SelectedAudience _ ->
            False

        SelectedAttribute _ ->
            False

        SelectedGroup _ ->
            True


groupFoldr : (Maybe Attribute -> Maybe Audience.Audience -> b -> b) -> b -> SelectedItemsGroup -> b
groupFoldr f acc itemsGroup =
    case itemsGroup of
        SingleAttribute attr ->
            f (Just attr) Nothing acc

        SingleAudience audience ->
            f Nothing (Just audience) acc

        ItemsGroup _ _ subnodes ->
            NonemptyList.foldr (\group listAcc -> groupFoldr f listAcc group) acc subnodes


groupMap : (Maybe Attribute -> Maybe Audience.Audience -> SelectedItemsGroup -> SelectedItemsGroup) -> SelectedItemsGroup -> SelectedItemsGroup
groupMap f itemsGroup =
    case itemsGroup of
        SingleAttribute attr ->
            f (Just attr) Nothing itemsGroup

        SingleAudience audience ->
            f Nothing (Just audience) itemsGroup

        ItemsGroup grouping groupName subnodes ->
            ItemsGroup grouping groupName (NonemptyList.map (groupMap f) subnodes)


getAttributesFromGroup : SelectedItemsGroup -> List Attribute
getAttributesFromGroup =
    groupFoldr
        (\maybeAttr _ ->
            Maybe.unwrap identity (::) maybeAttr
        )
        []


getAudiencesFromGroup : SelectedItemsGroup -> List Audience.Audience
getAudiencesFromGroup =
    groupFoldr (always (Maybe.unwrap identity (::))) []


getCaptionFromGroup : SelectedItemsGroup -> Caption
getCaptionFromGroup group =
    case group of
        ItemsGroup _ _ ( SingleAttribute attr, [] ) ->
            AttributeBrowser.getXBItemFromAttribute attr
                |> .caption

        ItemsGroup _ _ ( SingleAudience audience, [] ) ->
            Caption.create
                { name = audience.name
                , fullName = audience.name
                , subtitle = Nothing
                }

        ItemsGroup grouping groupName groups ->
            NonemptyList.map getCaptionFromGroup groups
                |> Caption.fromGroupOfCaptions grouping
                |> Maybe.unwrap identity Caption.setName groupName

        SingleAudience audience ->
            Caption.create
                { name = audience.name
                , fullName = audience.name
                , subtitle = Nothing
                }

        SingleAttribute attr ->
            AttributeBrowser.getXBItemFromAttribute attr
                |> .caption


isSelected : SelectedItem -> List SelectedItem -> Bool
isSelected item items =
    let
        isSelected_ : SelectedItemsGroup -> Bool
        isSelected_ group =
            case group of
                ItemsGroup _ _ children ->
                    item == SelectedGroup group || NonemptyList.any isSelected_ children

                SingleAttribute _ ->
                    item == SelectedGroup group

                SingleAudience _ ->
                    item == SelectedGroup group
    in
    List.any
        (\itemToCheck ->
            case itemToCheck of
                SelectedGroup group ->
                    isSelected_ group

                _ ->
                    itemToCheck == item
        )
        items


removeItem : SelectedItem -> List SelectedItem -> List SelectedItem
removeItem item items =
    let
        removeItem_ : SelectedItemsGroup -> Maybe SelectedItemsGroup
        removeItem_ group =
            if item == SelectedGroup group then
                Nothing

            else
                case group of
                    ItemsGroup logicOperator groupName children ->
                        NonemptyList.filterMap removeItem_ children
                            |> Maybe.map (ItemsGroup logicOperator groupName)

                    _ ->
                        Just group
    in
    items
        |> List.filterMap
            (\item_ ->
                if item_ == item then
                    Nothing

                else
                    case item_ of
                        SelectedGroup group ->
                            removeItem_ group
                                |> Maybe.map SelectedGroup

                        _ ->
                            Just item_
            )


toggleItemInclusion : SelectedItem -> List SelectedItem -> List SelectedItem
toggleItemInclusion itemToToggle selectedItems =
    let
        mapHelp : SelectedItemsGroup -> SelectedItemsGroup
        mapHelp group =
            if itemToToggle == SelectedGroup group then
                let
                    isAnyAttributeExcludedInGroup =
                        groupFoldr
                            (\maybeAttr maybeAudience acc ->
                                case ( maybeAttr, maybeAudience ) of
                                    ( Just attr, Nothing ) ->
                                        attr.isExcluded || acc

                                    ( Nothing, Just _ ) ->
                                        acc

                                    ( Just attr, Just _ ) ->
                                        attr.isExcluded || acc

                                    ( Nothing, Nothing ) ->
                                        acc
                            )
                            False
                            group
                in
                groupMap
                    (\maybeAttr maybeAudience whateverItemsGroup ->
                        case ( maybeAttr, maybeAudience ) of
                            ( Just attr, _ ) ->
                                SingleAttribute { attr | isExcluded = not isAnyAttributeExcludedInGroup }

                            ( Nothing, Just audience ) ->
                                SingleAudience audience

                            _ ->
                                whateverItemsGroup
                    )
                    group

            else
                case group of
                    ItemsGroup operator _ children ->
                        -- Always remove the title of the group
                        ItemsGroup operator Nothing (NonemptyList.map mapHelp children)

                    _ ->
                        group

        replaceSelectedItemGroupTitleWithNothing : SelectedItemsGroup -> SelectedItemsGroup
        replaceSelectedItemGroupTitleWithNothing group =
            case group of
                ItemsGroup operator _ children ->
                    ItemsGroup operator Nothing children

                _ ->
                    group
    in
    selectedItems
        |> List.map
            (\selectedItem ->
                if selectedItem == itemToToggle then
                    case selectedItem of
                        SelectedAttribute attr ->
                            SelectedAttribute { attr | isExcluded = not attr.isExcluded }

                        SelectedAudience _ ->
                            selectedItem

                        SelectedAverage _ ->
                            selectedItem

                        SelectedGroup group ->
                            let
                                isAnyAttributeExcludedInGroup =
                                    groupFoldr
                                        (\maybeAttr maybeAudience acc ->
                                            case ( maybeAttr, maybeAudience ) of
                                                ( Just attr, Nothing ) ->
                                                    attr.isExcluded || acc

                                                ( Nothing, Just _ ) ->
                                                    acc

                                                ( Just attr, Just _ ) ->
                                                    attr.isExcluded || acc

                                                ( Nothing, Nothing ) ->
                                                    acc
                                        )
                                        False
                                        group
                            in
                            SelectedGroup <|
                                replaceSelectedItemGroupTitleWithNothing <|
                                    groupMap
                                        (\maybeAttr maybeAudience whateverItemsGroup ->
                                            case ( maybeAttr, maybeAudience ) of
                                                ( Just attr, _ ) ->
                                                    SingleAttribute { attr | isExcluded = not isAnyAttributeExcludedInGroup }

                                                ( Nothing, Just audience ) ->
                                                    SingleAudience audience

                                                _ ->
                                                    whateverItemsGroup
                                        )
                                        group

                else
                    case selectedItem of
                        SelectedGroup group ->
                            mapHelp group
                                |> SelectedGroup

                        _ ->
                            selectedItem
            )


getExpressionFromGroup : SelectedItemsGroup -> Expression.Expression
getExpressionFromGroup group =
    case group of
        ItemsGroup grouping _ groups ->
            let
                connectByGrouping =
                    case grouping of
                        Split ->
                            NonemptyList.head

                        Or ->
                            Expression.unionMany

                        And ->
                            Expression.intersectionMany
            in
            NonemptyList.map getExpressionFromGroup groups
                |> connectByGrouping

        SingleAttribute attr ->
            AttributeBrowser.getXBItemFromAttribute attr
                |> .expression

        SingleAudience audience ->
            audience.expression


maxAttributeBrowserHistoryLength : Int
maxAttributeBrowserHistoryLength =
    20


init : SelectedItems -> IdSet WaveCodeTag -> IdSet LocationCodeTag -> Model
init initialSelectedItems waves locations =
    UndoRedo.init maxAttributeBrowserHistoryLength
        { activeWaves = waves
        , activeLocations = locations
        , activeTab = AttributesTab
        , selectedItems = initialSelectedItems
        , originalSelectedItemsBeforeEditing = initialSelectedItems
        , errorMessage = Nothing
        , activeGrouping = Split
        , incompatibilityWarningNote = Nothing
        , groupingPanelWarning = NoWarning
        , attributeBrowserLoadingAttributes = False
        , activeDropdown = Nothing
        , groupingItemWith = Nothing
        , dnd = dndSystem.model
        , renamingItems = []
        }


type Msg
    = SetActiveTab ModalTab
    | ToggleItem SelectedItem
    | ToggleInclusion SelectedItem
    | ShowDisabledWarningInAB
    | ToggleAttributes (List Attribute)
    | AddAttributes (List Attribute)
    | LoadingAttributes Bool
    | ClearAll
    | ToggleAverage AttributeBrowser.Average
    | SetDecodingError String
    | IncompatibilityWarningNoteOpened AttributeBrowser.WarningNote
    | CloseIncompatibilityWarningNote
    | ComplexMainGroupingSelected Grouping
    | GroupingSelected Grouping
    | GroupItems Grouping SelectedItem SelectedItem
    | ChangeGroupingForGroup Grouping SelectedItem
    | CloseDropdown
    | StartGroupItemWith SelectedItem
    | SelectItemForBulkGrouping SelectedItem
    | CancelGroupingWith
    | ApplyGroupingWith
    | Ungroup SelectedItem
    | DragAndDropMsg (XB2.Share.DragAndDrop.Move.Msg (GroupingPanel.Item SelectedItem) (GroupingPanel.Item SelectedItem))
    | RenameItem SelectedItem XB2GroupingPanel.ElementToFocus (Maybe String)
    | FinishTour
    | ToggleFixedPageDropdown (DropdownMenu Msg)
    | CheckWarningState Int
    | UndoChangesInAttributeBrowser
    | RedoChangesInAttributeBrowser
    | NoOp


clearDecodingError : ( Model, Cmd msg ) -> ( Model, Cmd msg )
clearDecodingError =
    Tuple.mapFirst (UndoRedo.updateCurrent (\m -> { m | errorMessage = Nothing }))


closeDropdown : Model -> Model
closeDropdown model =
    UndoRedo.updateCurrent (\m -> { m | activeDropdown = Nothing }) model


itemToGroupable : SelectedItem -> Maybe (NonEmpty SelectedItemsGroup)
itemToGroupable item =
    case item of
        SelectedAttribute attr ->
            Just <| NonemptyList.singleton (SingleAttribute attr)

        SelectedGroup group ->
            Just <| NonemptyList.singleton group

        SelectedAudience audience ->
            Just <| NonemptyList.singleton (SingleAudience audience)

        SelectedAverage _ ->
            Nothing


groupItemWith : SelectedItem -> SelectedItem -> Model -> ( Model, Cmd msg )
groupItemWith selected active model =
    let
        createNewGroup : SelectedItem -> Maybe SelectedItemsGroup
        createNewGroup selectedItem =
            itemToGroupable selectedItem
                |> Maybe.map
                    (\firstItemInNewGroup ->
                        case ( selectedItem, itemToGroupable active ) of
                            ( SelectedGroup (ItemsGroup grouping groupName group), Just activeForGrouping ) ->
                                NonemptyList.append group activeForGrouping
                                    |> ItemsGroup grouping groupName

                            _ ->
                                [ active, selected ]
                                    |> List.filter ((/=) selected)
                                    |> List.filterMap itemToGroupable
                                    |> List.foldl (\a b -> NonemptyList.append b a) firstItemInNewGroup
                                    |> ItemsGroup And Nothing
                    )

        cleanFromActive : SelectedItemsGroup -> Maybe SelectedItemsGroup
        cleanFromActive item =
            if SelectedGroup item == active then
                Nothing

            else
                case item of
                    ItemsGroup grouping groupName group ->
                        NonemptyList.filterMap cleanFromActive group
                            |> Maybe.map (ItemsGroup grouping groupName)

                    _ ->
                        Just item

        replaceWithGrouped : SelectedItemsGroup -> Maybe SelectedItemsGroup
        replaceWithGrouped item =
            let
                selectedItem : SelectedItem
                selectedItem =
                    SelectedGroup item
            in
            if List.member selectedItem [ active, selected ] && selectedItem /= selected then
                Nothing

            else if selectedItem == selected then
                cleanFromActive item
                    |> Maybe.unwrap (createNewGroup selectedItem) (SelectedGroup >> createNewGroup)

            else
                case item of
                    SingleAudience _ ->
                        Just item

                    SingleAttribute _ ->
                        Just item

                    ItemsGroup grouping groupName group ->
                        NonemptyList.filterMap replaceWithGrouped group
                            |> Maybe.map (ItemsGroup grouping groupName)
    in
    UndoRedo.commit UndoEvent.BrowserGroupItemWithAnother
        (\m ->
            { m
                | selectedItems =
                    m.selectedItems
                        |> List.filterMap
                            (\item ->
                                case item of
                                    SelectedGroup ((ItemsGroup grouping groupName group) as sgItem) ->
                                        if item == active then
                                            Nothing

                                        else
                                            replaceWithGrouped sgItem
                                                |> Maybe.orElse
                                                    (NonemptyList.filterMap replaceWithGrouped group
                                                        |> Maybe.map (ItemsGroup grouping groupName)
                                                    )
                                                |> Maybe.map SelectedGroup

                                    SelectedGroup sgItem ->
                                        if item == active then
                                            Nothing

                                        else
                                            replaceWithGrouped sgItem
                                                |> Maybe.map SelectedGroup

                                    _ ->
                                        if List.member item [ active, selected ] && item /= selected then
                                            Nothing

                                        else if item == selected then
                                            createNewGroup item
                                                |> Maybe.map SelectedGroup

                                        else
                                            Just item
                            )
                , groupingItemWith = Nothing
            }
        )
        model
        |> Cmd.pure


groupItemsWith : SelectedItems -> SelectedItem -> Model -> ( Model, Cmd msg )
groupItemsWith selected active model =
    let
        checkNesting :
            SelectedItemsGroup
            -> ( Int, Maybe { nesting : Int, item : SelectedItem } )
            -> ( Int, Maybe { nesting : Int, item : SelectedItem } )
        checkNesting selectedItemsGroup ( nesting, maybeDeepestSelection ) =
            let
                selectedItem =
                    SelectedGroup selectedItemsGroup
            in
            if List.member selectedItem selected || selectedItem == active then
                case maybeDeepestSelection of
                    Just soFar ->
                        if soFar.nesting < nesting then
                            ( nesting, Just { nesting = nesting, item = selectedItem } )

                        else
                            ( nesting, maybeDeepestSelection )

                    Nothing ->
                        ( nesting, Just { nesting = nesting, item = selectedItem } )

            else
                case selectedItemsGroup of
                    ItemsGroup _ _ children ->
                        NonemptyList.foldr checkNesting ( nesting + 1, maybeDeepestSelection ) children

                    _ ->
                        ( nesting, maybeDeepestSelection )

        groupDestination : SelectedItem
        groupDestination =
            UndoRedo.current model
                |> .selectedItems
                |> List.foldr
                    (\item acc ->
                        case item of
                            SelectedGroup groupItem ->
                                checkNesting groupItem ( 0, acc )
                                    |> Tuple.second

                            _ ->
                                acc
                    )
                    Nothing
                |> Maybe.unwrap active .item

        createNewGroup : SelectedItem -> Maybe SelectedItemsGroup
        createNewGroup selectedItem =
            itemToGroupable selectedItem
                |> Maybe.map
                    (\firstItemInNewGroup ->
                        (active :: selected)
                            |> List.filter ((/=) groupDestination)
                            |> List.filterMap itemToGroupable
                            |> List.foldl (\a b -> NonemptyList.append b a) firstItemInNewGroup
                            |> ItemsGroup And Nothing
                    )

        replaceWithGrouped : SelectedItemsGroup -> Maybe SelectedItemsGroup
        replaceWithGrouped item =
            let
                selectedItem : SelectedItem
                selectedItem =
                    SelectedGroup item
            in
            if List.member selectedItem (active :: selected) && selectedItem /= groupDestination then
                Nothing

            else if selectedItem == groupDestination then
                createNewGroup selectedItem

            else
                case item of
                    SingleAudience _ ->
                        Just item

                    SingleAttribute _ ->
                        Just item

                    ItemsGroup grouping groupName group ->
                        NonemptyList.filterMap replaceWithGrouped group
                            |> Maybe.map (ItemsGroup grouping groupName)
    in
    UndoRedo.commit UndoEvent.BrowserGroupItemWithOthers
        (\m ->
            { m
                | selectedItems =
                    m.selectedItems
                        |> List.filterMap
                            (\item ->
                                case item of
                                    SelectedAverage _ ->
                                        Just item

                                    SelectedGroup ((ItemsGroup grouping groupName group) as sgItem) ->
                                        if item == active then
                                            case selected of
                                                [ SelectedAttribute _ ] ->
                                                    replaceWithGrouped sgItem
                                                        |> Maybe.orElse
                                                            (NonemptyList.filterMap replaceWithGrouped group
                                                                |> Maybe.map (ItemsGroup grouping groupName)
                                                            )
                                                        |> Maybe.map SelectedGroup

                                                _ ->
                                                    Nothing

                                        else
                                            replaceWithGrouped sgItem
                                                |> Maybe.orElse
                                                    (NonemptyList.filterMap replaceWithGrouped group
                                                        |> Maybe.map (ItemsGroup grouping groupName)
                                                    )
                                                |> Maybe.map SelectedGroup

                                    SelectedGroup sgItem ->
                                        if item == active then
                                            Nothing

                                        else
                                            replaceWithGrouped sgItem
                                                |> Maybe.map SelectedGroup

                                    _ ->
                                        if List.member item (active :: selected) && item /= groupDestination then
                                            Nothing

                                        else if item == groupDestination then
                                            createNewGroup item
                                                |> Maybe.map SelectedGroup

                                        else
                                            Just item
                            )
                , groupingItemWith = Nothing
            }
        )
        model
        |> Cmd.pure


update : Config msg -> Route -> Flags -> Store -> Msg -> Model -> ( Model, Cmd msg )
update config route flags store msg model =
    case msg of
        SetActiveTab newTab ->
            Cmd.pure <|
                UndoRedo.updateCurrent
                    (\m ->
                        { m
                            | activeTab = newTab
                        }
                    )
                    model

        ToggleInclusion item ->
            -- Toggles the inclusion/exclusion of a SelectedAttribute inside the modal selectedItems
            UndoRedo.commit UndoEvent.BrowserInclusionOfItemToggled
                (\m ->
                    { m
                        | selectedItems =
                            toggleItemInclusion item m.selectedItems
                    }
                )
                model
                |> closeDropdown
                |> Cmd.pure

        UndoChangesInAttributeBrowser ->
            UndoRedo.undo model
                |> closeDropdown
                |> Cmd.with (Analytics.trackEvent flags route Place.CrosstabBuilder Analytics.UndoClickedInAttrBrowser)

        RedoChangesInAttributeBrowser ->
            UndoRedo.redo model
                |> closeDropdown
                |> Cmd.with (Analytics.trackEvent flags route Place.CrosstabBuilder Analytics.RedoClickedInAttrBrowser)

        ToggleItem item ->
            UndoRedo.commit UndoEvent.BrowserItemToggled
                (\m ->
                    { m
                        | selectedItems =
                            if isSelected item m.selectedItems then
                                removeItem item m.selectedItems

                            else
                                m.selectedItems ++ [ item ]
                    }
                )
                model
                |> closeDropdown
                |> Cmd.pure
                |> clearDecodingError
                |> Cmd.addTrigger (config.itemToggled item (UndoRedo.current model |> .selectedItems))

        LoadingAttributes loading ->
            Cmd.pure (UndoRedo.updateCurrent (\m -> { m | attributeBrowserLoadingAttributes = loading }) model)

        AddAttributes attrs ->
            let
                insertableAttrs : List SelectedItem
                insertableAttrs =
                    List.map SelectedAttribute attrs

                getMaybeAttributeFullCodeWithNamespace : SelectedItem -> Maybe String
                getMaybeAttributeFullCodeWithNamespace item =
                    case item of
                        SelectedAttribute attr ->
                            [ Namespace.codeToString attr.namespaceCode
                            , XB2.Share.Data.Id.unwrap attr.codes.questionCode
                            , XB2.Share.Data.Id.unwrap attr.codes.datapointCode
                            ]
                                |> String.concat
                                |> (\almostCode ->
                                        almostCode
                                            ++ Maybe.unwrap ""
                                                (XB2.Share.Data.Id.unwrap
                                                    >> (++) XB2.Share.Data.Labels.p2Separator
                                                )
                                                attr.codes.suffixCode
                                   )
                                |> Just

                        _ ->
                            Nothing

                resolveSelectedItems : List SelectedItem -> List SelectedItem
                resolveSelectedItems selectedItems =
                    selectedItems
                        |> List.filter
                            (\item ->
                                not <|
                                    List.member
                                        (getMaybeAttributeFullCodeWithNamespace
                                            item
                                        )
                                        (List.map getMaybeAttributeFullCodeWithNamespace
                                            insertableAttrs
                                        )
                            )
                        |> flip (++) insertableAttrs
            in
            insertableAttrs
                |> List.foldr (Cmd.addTrigger << flip config.itemToggled (UndoRedo.current model |> .selectedItems))
                    (Cmd.pure <|
                        UndoRedo.commit
                            UndoEvent.BrowserAttributesAdded
                            (\m ->
                                { m
                                    | selectedItems =
                                        if List.isEmpty m.selectedItems then
                                            insertableAttrs

                                        else
                                            resolveSelectedItems m.selectedItems
                                    , errorMessage = Nothing
                                }
                            )
                            model
                    )

        ToggleAttributes attrs ->
            let
                insertableAttrs : List SelectedItem
                insertableAttrs =
                    List.map SelectedAttribute attrs

                removeOrAddAttrsToSelectedItems :
                    List SelectedItem
                    -> List SelectedItem
                    -> List SelectedItem
                removeOrAddAttrsToSelectedItems attrsToggled selectedItems =
                    case attrsToggled of
                        [] ->
                            selectedItems

                        (SelectedAttribute attribute) :: xs ->
                            if
                                List.member
                                    (SelectedAttribute attribute
                                        |> getMaybeAttributeFullCodeWithNamespace
                                    )
                                    (List.map getMaybeAttributeFullCodeWithNamespace
                                        selectedItems
                                    )
                            then
                                removeOrAddAttrsToSelectedItems xs
                                    (List.filter
                                        (\item ->
                                            getMaybeAttributeFullCodeWithNamespace item
                                                /= getMaybeAttributeFullCodeWithNamespace
                                                    (SelectedAttribute attribute)
                                        )
                                        selectedItems
                                    )

                            else
                                removeOrAddAttrsToSelectedItems xs
                                    (selectedItems ++ [ SelectedAttribute attribute ])

                        _ :: xs ->
                            removeOrAddAttrsToSelectedItems xs
                                selectedItems

                getMaybeAttributeFullCodeWithNamespace : SelectedItem -> Maybe String
                getMaybeAttributeFullCodeWithNamespace item =
                    case item of
                        SelectedAttribute attr ->
                            [ Namespace.codeToString attr.namespaceCode
                            , XB2.Share.Data.Id.unwrap attr.codes.questionCode
                            , XB2.Share.Data.Id.unwrap attr.codes.datapointCode
                            ]
                                |> String.concat
                                |> (\almostCode ->
                                        almostCode
                                            ++ Maybe.unwrap ""
                                                (XB2.Share.Data.Id.unwrap
                                                    >> (++) XB2.Share.Data.Labels.p2Separator
                                                )
                                                attr.codes.suffixCode
                                   )
                                |> Just

                        _ ->
                            Nothing
            in
            insertableAttrs
                |> List.foldr
                    (Cmd.addTrigger
                        << flip config.itemToggled
                            (UndoRedo.current model |> .selectedItems)
                    )
                    (Cmd.pure
                        (UndoRedo.commit UndoEvent.BrowserAttributesToggled
                            (\m ->
                                { m
                                    | selectedItems =
                                        removeOrAddAttrsToSelectedItems
                                            insertableAttrs
                                            m.selectedItems
                                    , errorMessage = Nothing
                                }
                            )
                            model
                        )
                    )

        ClearAll ->
            Cmd.pure
                (UndoRedo.commit UndoEvent.BrowserClearedAll
                    (\m ->
                        { m
                            | selectedItems = []
                            , groupingItemWith = Nothing
                            , renamingItems = []
                        }
                    )
                    model
                )

        ToggleAverage average ->
            let
                item : SelectedItem
                item =
                    SelectedAverage average

                newSelectedItems =
                    if List.member (SelectedAverage average) (UndoRedo.current model |> .selectedItems) then
                        UndoRedo.current model |> .selectedItems |> List.filter ((/=) item)

                    else
                        (UndoRedo.current model |> .selectedItems) ++ [ item ]

                willContainAverage =
                    List.any isSelectedAverage newSelectedItems
            in
            ( UndoRedo.commit UndoEvent.BrowserToggledAverage
                (\m ->
                    { m
                        | selectedItems = newSelectedItems
                        , activeGrouping =
                            if willContainAverage then
                                Split

                            else
                                m.activeGrouping
                    }
                )
                model
            , Cmd.none
            )
                |> clearDecodingError
                |> Cmd.addTrigger (config.itemToggled item (UndoRedo.current model |> .selectedItems))

        ShowDisabledWarningInAB ->
            model
                |> setModalBrowserWarning ClickedDisabledAudience
                |> Cmd.pure

        SetDecodingError err ->
            UndoRedo.updateCurrent (\m -> { m | errorMessage = Just err }) model
                |> Cmd.pure

        IncompatibilityWarningNoteOpened note ->
            Cmd.pure <|
                UndoRedo.updateCurrent
                    (\m ->
                        { m
                            | incompatibilityWarningNote = Just note
                        }
                    )
                    model

        CloseIncompatibilityWarningNote ->
            Cmd.pure <|
                UndoRedo.updateCurrent
                    (\m ->
                        { m
                            | incompatibilityWarningNote = Nothing
                        }
                    )
                    model

        GroupingSelected grouping ->
            Cmd.pure <|
                UndoRedo.commit UndoEvent.BrowserGroupingSelected (\m -> { m | activeGrouping = grouping }) model

        ComplexMainGroupingSelected grouping ->
            let
                unwrapGroupType item =
                    case item of
                        ItemsGroup _ _ _ ->
                            SelectedGroup item

                        SingleAttribute attr ->
                            SelectedAttribute attr

                        SingleAudience audience ->
                            SelectedAudience audience
            in
            Cmd.pure <|
                UndoRedo.updateCurrent
                    (\m ->
                        { m
                            | selectedItems =
                                if List.any isSelectedGroup m.selectedItems && (List.length m.selectedItems == 1) then
                                    m.selectedItems
                                        |> List.fastConcatMap
                                            (\item ->
                                                case item of
                                                    SelectedGroup (ItemsGroup _ groupName children) ->
                                                        if grouping == Split then
                                                            NonemptyList.map unwrapGroupType children
                                                                |> NonemptyList.toList

                                                        else
                                                            [ SelectedGroup <| ItemsGroup grouping groupName children ]

                                                    _ ->
                                                        [ item ]
                                            )

                                else
                                    m.selectedItems
                                        |> List.filterMap
                                            (\item ->
                                                case item of
                                                    SelectedAttribute attr ->
                                                        Just <| SingleAttribute attr

                                                    SelectedAudience audience ->
                                                        Just <| SingleAudience audience

                                                    SelectedAverage _ ->
                                                        Nothing

                                                    SelectedGroup group ->
                                                        Just group
                                            )
                                        |> NonemptyList.fromList
                                        |> Maybe.unwrap m.selectedItems (ItemsGroup grouping Nothing >> SelectedGroup >> List.singleton)
                        }
                    )
                    model

        GroupItems grouping item1 item2 ->
            UndoRedo.commit UndoEvent.BrowserGroupItemWithAnother
                (\m ->
                    { m
                        | selectedItems =
                            m.selectedItems
                                |> List.filter ((/=) item2)
                                |> List.map
                                    (\item ->
                                        if item == item1 then
                                            case ( itemToGroupable item, itemToGroupable item2 ) of
                                                ( Just itemToGroup1, Just itemToGroup2 ) ->
                                                    SelectedGroup <| ItemsGroup grouping Nothing <| NonemptyList.append itemToGroup1 itemToGroup2

                                                _ ->
                                                    item

                                        else
                                            item
                                    )
                    }
                )
                model
                |> Cmd.pure

        ChangeGroupingForGroup grouping group ->
            let
                changeGroupingForGroup item =
                    case item of
                        ItemsGroup originalGrouping groupName children ->
                            if SelectedGroup item == group then
                                ItemsGroup grouping groupName children

                            else
                                ItemsGroup originalGrouping groupName (NonemptyList.map changeGroupingForGroup children)

                        SingleAttribute _ ->
                            item

                        SingleAudience _ ->
                            item
            in
            Cmd.pure <|
                UndoRedo.commit UndoEvent.BrowserChangedGroupingForGroup
                    (\m ->
                        { m
                            | selectedItems =
                                m.selectedItems
                                    |> List.map
                                        (\item ->
                                            case item of
                                                SelectedGroup groupItem ->
                                                    SelectedGroup <| changeGroupingForGroup groupItem

                                                _ ->
                                                    item
                                        )
                        }
                    )
                    model

        CloseDropdown ->
            Cmd.pure (closeDropdown model)

        StartGroupItemWith item ->
            Cmd.pure <|
                UndoRedo.updateCurrent
                    (\m ->
                        { m
                            | groupingItemWith = Just ( [], item )
                            , activeDropdown = Nothing
                        }
                    )
                    model

        SelectItemForBulkGrouping item ->
            Cmd.pure <|
                UndoRedo.updateCurrent
                    (\m ->
                        { m
                            | groupingItemWith =
                                m.groupingItemWith
                                    |> Maybe.andThen
                                        (\( selected, active ) ->
                                            if item /= active then
                                                Just ( List.toggle item selected, active )

                                            else
                                                m.groupingItemWith
                                        )
                        }
                    )
                    model

        CancelGroupingWith ->
            Cmd.pure (UndoRedo.updateCurrent (\m -> { m | groupingItemWith = Nothing }) model)

        ApplyGroupingWith ->
            case UndoRedo.current model |> .groupingItemWith of
                Just ( selected, active ) ->
                    groupItemsWith selected active model

                Nothing ->
                    Cmd.pure model

        Ungroup item ->
            let
                ungroupedItems =
                    case item of
                        SelectedGroup group ->
                            groupFoldr
                                (\maybeAttr maybeAudience acc ->
                                    case ( maybeAttr, maybeAudience ) of
                                        ( Just attr, Nothing ) ->
                                            SelectedAttribute attr :: acc

                                        ( Nothing, Just audience ) ->
                                            SelectedAudience audience :: acc

                                        ( Just attr, Just audience ) ->
                                            SelectedAttribute attr :: SelectedAudience audience :: acc

                                        ( Nothing, Nothing ) ->
                                            acc
                                )
                                []
                                group

                        _ ->
                            []
            in
            UndoRedo.commit UndoEvent.BrowserUngroupedItem
                (\m ->
                    { m
                        | selectedItems =
                            (m.selectedItems
                                |> removeItem item
                            )
                                ++ ungroupedItems
                    }
                )
                model
                |> closeDropdown
                |> Cmd.pure

        DragAndDropMsg dndMsg ->
            let
                ( dndReturn, newDndModel, dndCmd ) =
                    dndSystem.update dndMsg (UndoRedo.current model |> .dnd)
            in
            case dndReturn of
                Just { dropListId, dragItem } ->
                    UndoRedo.updateCurrent (\m -> { m | dnd = newDndModel }) model
                        |> groupItemWith dropListId.item dragItem.item
                        |> Cmd.add (Cmd.map config.msg dndCmd)

                Nothing ->
                    UndoRedo.updateCurrent (\m -> { m | dnd = newDndModel }) model
                        |> Cmd.with (Cmd.map config.msg dndCmd)

        NoOp ->
            Cmd.pure model

        RenameItem item focusing name ->
            let
                renameSelectedItem : SelectedItem -> SelectedItem
                renameSelectedItem it =
                    if it == item then
                        case it of
                            SelectedGroup group ->
                                case group of
                                    ItemsGroup grouping _ items ->
                                        if Maybe.isJust name then
                                            SelectedGroup <| ItemsGroup grouping name items

                                        else
                                            SelectedGroup group

                                    _ ->
                                        SelectedGroup group

                            _ ->
                                it

                    else
                        it

                updatedRenamingItems : SelectedItems
                updatedRenamingItems =
                    if List.member item (UndoRedo.current model |> .renamingItems) then
                        if Maybe.isNothing name then
                            List.remove (renameSelectedItem item) (UndoRedo.current model |> .renamingItems)

                        else
                            List.map renameSelectedItem (UndoRedo.current model |> .renamingItems)

                    else if Maybe.isNothing name then
                        UndoRedo.current model |> .renamingItems

                    else
                        renameSelectedItem item :: (UndoRedo.current model |> .renamingItems)

                focusCmd : Cmd Msg
                focusCmd =
                    case focusing of
                        Just id ->
                            Task.attempt (always NoOp) <| Dom.focus id

                        Nothing ->
                            Cmd.none
            in
            case name of
                Nothing ->
                    UndoRedo.commit UndoEvent.BrowserRenamedItems
                        (\m ->
                            { m
                                | renamingItems = updatedRenamingItems
                                , selectedItems = List.map renameSelectedItem m.selectedItems
                            }
                        )
                        model
                        |> Cmd.with (Cmd.map config.msg focusCmd)

                Just _ ->
                    UndoRedo.updateCurrent
                        (\m ->
                            { m
                                | renamingItems = updatedRenamingItems
                                , selectedItems = List.map renameSelectedItem m.selectedItems
                            }
                        )
                        model
                        |> Cmd.with (Cmd.map config.msg focusCmd)

        FinishTour ->
            case store.userSettings of
                RemoteData.Success settings ->
                    ( model
                    , Cmd.batch <|
                        List.map Cmd.perform
                            [ config.updateUserSettings settings
                            , config.msg ClearAll
                            ]
                    )

                _ ->
                    Cmd.pure model

        ToggleFixedPageDropdown dropDownMenu ->
            if Maybe.isNothing (UndoRedo.current model |> .groupingItemWith) then
                UndoRedo.updateCurrent
                    (\m ->
                        { m
                            | activeDropdown = Just <| Maybe.unwrap dropDownMenu (DropdownMenu.toggle dropDownMenu) m.activeDropdown
                        }
                    )
                    model
                    |> Cmd.pure

            else
                Cmd.pure model

        CheckWarningState visibleTickDecrement ->
            case UndoRedo.current model |> .groupingPanelWarning of
                NoWarning ->
                    Cmd.pure model

                WarningVisible state ->
                    if state.msTTL - visibleTickDecrement <= 0 then
                        Cmd.pure (UndoRedo.updateCurrent (\m -> { m | groupingPanelWarning = NoWarning }) model)

                    else
                        Cmd.pure (UndoRedo.updateCurrent (\m -> { m | groupingPanelWarning = WarningVisible { state | msTTL = state.msTTL - visibleTickDecrement } }) model)


avgToItem : AttributeBrowser.Average -> GroupingPanel.Item SelectedItem
avgToItem average =
    let
        label =
            case average of
                AttributeBrowser.AvgWithoutSuffixes q ->
                    q.questionLabel

                AttributeBrowser.AvgWithSuffixes q dpInfo ->
                    q.questionLabel ++ XB2.Share.Data.Labels.p2Separator ++ dpInfo.datapointLabel
    in
    { item = SelectedAverage average
    , title = label
    , subtitle = Just "Average of "
    , type_ = GroupingPanel.Average
    }


itemsForGroupingPanel : SelectedItems -> List (GroupingPanel.Item SelectedItem)
itemsForGroupingPanel =
    let
        resolveReadyItem : SelectedItem -> GroupingPanel.Item SelectedItem
        resolveReadyItem item =
            let
                newSubtitle attr =
                    attr.datapointName
                        ++ (attr.suffixName
                                |> Maybe.map (\suf -> XB2.Share.Data.Labels.p2Separator ++ suf)
                                |> Maybe.withDefault ""
                           )
            in
            case item of
                SelectedAttribute attr ->
                    { item = item
                    , title = newSubtitle attr
                    , subtitle = Just attr.questionName
                    , type_ = GroupingPanel.Attribute
                    }

                SelectedAudience audience ->
                    { item = item
                    , title = audience.name
                    , subtitle = Nothing
                    , type_ =
                        if Set.Any.member AudienceFlag.AuthoredAudience audience.flags then
                            GroupingPanel.AudienceMy

                        else
                            GroupingPanel.AudienceDefault
                    }

                SelectedAverage average ->
                    avgToItem average

                SelectedGroup (SingleAttribute attr) ->
                    { item = item
                    , title = Caption.getFullName <| getCaptionFromGroup (SingleAttribute attr)
                    , subtitle = Just attr.questionName
                    , type_ = GroupingPanel.Group
                    }

                SelectedGroup group ->
                    { item = item
                    , title = Caption.getFullName <| getCaptionFromGroup group
                    , subtitle = Nothing
                    , type_ = GroupingPanel.Group
                    }
    in
    List.map resolveReadyItem


warningView : WarningState -> Maybe (Html msg)
warningView warning =
    let
        warningTypeView : Warning -> Html msg
        warningTypeView w =
            case w of
                PossibleIncompatibilities ->
                    Html.span []
                        [ Html.text "It looks like you are trying to add some attributes from a new dataset. This is still possible, but it could create some "
                        , Html.strong [] [ Html.text "warnings" ]
                        , Html.text " and/or "
                        , Html.strong [] [ Html.text "data incompatibilities." ]
                        ]

                ClickedDisabledAudience ->
                    AudienceBrowser.clickedDisabledAudienceText "crosstab"
    in
    case warning of
        NoWarning ->
            Nothing

        WarningVisible state ->
            Just <| warningTypeView state.warning


applyButtons : Config msg -> Model -> List (GroupingPanel.ConfirmButton msg) -> List (GroupingPanel.ConfirmButton msg)
applyButtons config model buttons =
    case UndoRedo.current model |> .groupingItemWith of
        Just groupingItemWith ->
            [ { label = "Cancel"
              , onClick = config.msg CancelGroupingWith
              , disabled = False
              }
            , { label = "Apply"
              , onClick = config.msg ApplyGroupingWith
              , disabled =
                    groupingItemWith
                        |> Tuple.first
                        |> List.isEmpty
              }
            ]

        Nothing ->
            buttons


toComplexExpressionPanelConfig : Config msg -> List Grouping -> StateForGroupingPanel msg -> GroupingPanel.Config SelectedItem msg -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
toComplexExpressionPanelConfig config singleItemGroupings { isAffixing, model } groupingPanelConfig_ =
    let
        isGroupingMode : Bool
        isGroupingMode =
            (UndoRedo.current model |> .groupingItemWith) /= Nothing

        isBeingRenamed item =
            List.member item (UndoRedo.current model |> .renamingItems)

        groupingPanelConfig =
            { groupingPanelConfig_ | buttons = applyButtons config model groupingPanelConfig_.buttons }

        activeGrouping =
            if (UndoRedo.current model |> .activeGrouping) == Split then
                List.head singleItemGroupings
                    |> Maybe.withDefault (UndoRedo.current model |> .activeGrouping)

            else
                UndoRedo.current model |> .activeGrouping
    in
    ( { config = groupingPanelConfig
      , noOp = config.noOp
      , getDndForItem =
            \index item ->
                let
                    htmlId =
                        "dnd-element-id--" ++ selectedItemToString item.item
                in
                { dndStates =
                    dndSystem.info (UndoRedo.current model |> .dnd |> .list)
                        |> Maybe.map
                            (\{ dropListId, dragItem } ->
                                [ ( "placeholder", dragItem == item )
                                , ( "dragover", dropListId == item && item /= dragItem )
                                ]
                            )
                        |> Maybe.withDefault []
                , dragEvents =
                    if isSelectedAverage item.item || isBeingRenamed item.item then
                        []

                    else
                        dndSystem.dragEvents item item index htmlId
                            |> List.map (Attrs.map config.msg)
                , dropEvents =
                    if isSelectedAverage item.item || isBeingRenamed item.item then
                        []

                    else
                        dndSystem.info (UndoRedo.current model |> .dnd |> .list)
                            |> Maybe.map
                                (\{ dragItem } ->
                                    if dragItem == item then
                                        []

                                    else
                                        dndSystem.dropEvents item index htmlId
                                            |> List.map (Attrs.map config.msg)
                                )
                            |> Maybe.withDefault []
                , isDragged =
                    dndSystem.info (UndoRedo.current model |> .dnd |> .list)
                        |> Maybe.unwrap False (.dragItem >> (==) item)
                , htmlId = htmlId
                }
      , renameItem = \item focusing -> config.msg << RenameItem item focusing
      , closeDropdown = config.msg CloseDropdown
      , itemsBeingRenamed = UndoRedo.current model |> .renamingItems |> itemsForGroupingPanel
      , updateUserSettings = config.updateUserSettings
      , clearAttributeBrowser = config.msg FinishTour
      , getItemChildren =
            \item ->
                case item of
                    SelectedGroup (SingleAttribute _) ->
                        Nothing

                    SelectedGroup (ItemsGroup grouping _ groupItems) ->
                        NonemptyList.map SelectedGroup groupItems
                            |> NonemptyList.toList
                            |> itemsForGroupingPanel
                            |> NonemptyList.fromList
                            |> Maybe.map
                                (\children ->
                                    { children = children, grouping = grouping }
                                )

                    _ ->
                        Nothing
      , isAffixing = isAffixing
      , singleItemGroupings =
            singleItemGroupings
                |> List.map
                    (\grouping { item, nextItem } ->
                        { grouping = grouping
                        , disabled = isGroupingMode || ((isSelectedAverage item || isSelectedAverage nextItem) && grouping /= Split)
                        , onClick =
                            if isSelectedAverage item || isSelectedAverage nextItem || isGroupingMode || (activeGrouping == Split && grouping == Split) then
                                config.noOp

                            else
                                GroupItems grouping item nextItem |> config.msg
                        }
                    )
      , insideGroupGroupings =
            [ And, Or ]
                |> List.map
                    (\grouping group ->
                        { grouping = grouping
                        , disabled = isGroupingMode
                        , onClick =
                            if isGroupingMode then
                                config.noOp

                            else
                                ChangeGroupingForGroup grouping group |> config.msg
                        }
                    )
      , getItemDropdown =
            \className item ->
                let
                    removeLabel =
                        case item of
                            SelectedAttribute _ ->
                                "Remove attribute"

                            SelectedAudience _ ->
                                "Remove audience"

                            SelectedAverage _ ->
                                "Remove average"

                            SelectedGroup (SingleAttribute _) ->
                                "Remove attribute"

                            SelectedGroup _ ->
                                "Remove group"

                    inclusionOptionView =
                        case item of
                            SelectedAttribute attr ->
                                DropdownItem.view
                                    [ DropdownItem.class dropdownMenuClass
                                    , DropdownItem.label
                                        (if attr.isExcluded then
                                            "Include"

                                         else
                                            "Exclude"
                                        )
                                    , DropdownItem.onClick <| ToggleInclusion item
                                    , DropdownItem.leftIcon
                                        (if attr.isExcluded then
                                            P2Icons.include

                                         else
                                            P2Icons.exclude
                                        )
                                    ]

                            SelectedAudience _ ->
                                Html.nothing

                            SelectedAverage _ ->
                                Html.nothing

                            SelectedGroup (SingleAttribute attr) ->
                                DropdownItem.view
                                    [ DropdownItem.class dropdownMenuClass
                                    , DropdownItem.label
                                        (if attr.isExcluded then
                                            "Include"

                                         else
                                            "Exclude"
                                        )
                                    , DropdownItem.onClick <| ToggleInclusion item
                                    , DropdownItem.leftIcon
                                        (if attr.isExcluded then
                                            P2Icons.include

                                         else
                                            P2Icons.exclude
                                        )
                                    ]

                            SelectedGroup (SingleAudience _) ->
                                Html.nothing

                            SelectedGroup group ->
                                let
                                    isAnyAttributeExcludedInGroup =
                                        groupFoldr
                                            (\maybeAttr maybeAudience acc ->
                                                case ( maybeAttr, maybeAudience ) of
                                                    ( Just attr, Nothing ) ->
                                                        attr.isExcluded || acc

                                                    ( Nothing, Just _ ) ->
                                                        acc

                                                    ( Just attr, Just _ ) ->
                                                        attr.isExcluded || acc

                                                    ( Nothing, Nothing ) ->
                                                        acc
                                            )
                                            False
                                            group
                                in
                                DropdownItem.view
                                    [ DropdownItem.class dropdownMenuClass
                                    , DropdownItem.label
                                        (if isAnyAttributeExcludedInGroup then
                                            "Include all"

                                         else
                                            "Exclude all"
                                        )
                                    , DropdownItem.onClick <| ToggleInclusion item
                                    , DropdownItem.leftIcon
                                        (if isAnyAttributeExcludedInGroup then
                                            P2Icons.include

                                         else
                                            P2Icons.exclude
                                        )
                                    ]

                    addUngroupForGroup : List (Html Msg) -> List (Html Msg)
                    addUngroupForGroup list =
                        case item of
                            SelectedGroup (ItemsGroup _ _ _) ->
                                list
                                    ++ [ DropdownItem.view
                                            [ DropdownItem.class dropdownMenuClass
                                            , DropdownItem.label "Ungroup group"
                                            , DropdownItem.onClick <| Ungroup item
                                            , DropdownItem.leftIcon P2Icons.ungroup
                                            ]
                                       ]

                            _ ->
                                list

                    dropDownId : String
                    dropDownId =
                        "complex-expression-grouping-panel-dd-menu--" ++ selectedItemToString item

                    isDDOpen : Bool
                    isDDOpen =
                        Maybe.unwrap False (DropdownMenu.isVisible dropDownId) (UndoRedo.current model |> .activeDropdown)

                    dropdownMenuClass =
                        WeakCss.addMany [ "dropdown", "options" ] className
                in
                Html.div
                    [ WeakCss.addMany [ "dropdown-cont" ] className
                        |> WeakCss.withStates [ ( "disabled", Maybe.isJust (UndoRedo.current model |> .groupingItemWith) ) ]
                    ]
                    [ DropdownMenu.with ToggleFixedPageDropdown
                        { id = dropDownId
                        , orientation = DropdownMenu.ToLeft
                        , screenBottomEdgeMinOffset = 80
                        , screenSideEdgeMinOffset = 200
                        , content =
                            Html.viewIf (Maybe.isNothing (UndoRedo.current model |> .groupingItemWith)) <|
                                Html.div
                                    [ dropdownMenuClass
                                        |> WeakCss.withActiveStates [ "dynamic" ]
                                    ]
                                    [ (((if isSelectedAverage item then
                                            []

                                         else
                                            [ DropdownItem.view
                                                [ DropdownItem.class dropdownMenuClass
                                                , DropdownItem.label "Group with"
                                                , DropdownItem.onClick <| StartGroupItemWith item
                                                , DropdownItem.leftIcon P2Icons.group
                                                ]
                                            ]
                                        )
                                            |> addUngroupForGroup
                                       )
                                        ++ [ inclusionOptionView
                                           , DropdownItem.view
                                                [ DropdownItem.class dropdownMenuClass
                                                , DropdownItem.label removeLabel
                                                , DropdownItem.onClick <| ToggleItem item
                                                , DropdownItem.leftIcon P2Icons.trash
                                                ]
                                           ]
                                      )
                                        |> Html.div
                                            [ WeakCss.nestMany [ "dropdown", "menu" ] className
                                            ]
                                    ]
                        , controlElementAttrs =
                            [ WeakCss.addMany [ "dropdown", "pill", "trigger-button" ] className
                                |> WeakCss.withStates [ ( "open", isDDOpen ) ]
                            , Attrs.attribute "aria-label" "Item options"
                            ]
                        , controlElementContent =
                            [ Html.div
                                [ WeakCss.addMany [ "dropdown", "pill", "trigger-button", "right-icon" ] className
                                    |> WeakCss.withStates [ ( "active", isDDOpen ) ]
                                ]
                                [ XB2.Share.Icons.icon []
                                    (if isDDOpen then
                                        P2Icons.ellipsisVerticalCircle

                                     else
                                        P2Icons.ellipsisVertical
                                    )
                                ]
                            ]
                        }
                    ]
                    |> Html.map config.msg
      , groupingWithState =
            \item ->
                UndoRedo.current model
                    |> .groupingItemWith
                    |> Maybe.map
                        (\( selected, active ) ->
                            { isSelected = List.member item selected
                            , isActive = active == item
                            , action =
                                if active == item || isSelectedAverage item then
                                    config.noOp

                                else
                                    config.msg <| SelectItemForBulkGrouping item
                            , canGrouping = not <| isSelectedAverage item
                            }
                        )
      , getItemIsExcluded =
            \item ->
                case item of
                    SelectedAttribute attr ->
                        Just attr.isExcluded

                    SelectedAudience _ ->
                        Nothing

                    SelectedAverage _ ->
                        Nothing

                    SelectedGroup (SingleAttribute attr) ->
                        Just attr.isExcluded

                    SelectedGroup (SingleAudience _) ->
                        Nothing

                    SelectedGroup _ ->
                        Nothing
      , isADropdownOpen = Maybe.isJust (UndoRedo.current model |> .activeDropdown)
      }
    , groupingPanelConfig
    )


getGroupingFromItem : SelectedItem -> Maybe Grouping
getGroupingFromItem item =
    case item of
        SelectedGroup (ItemsGroup groupingForGroup _ _) ->
            Just groupingForGroup

        _ ->
            Nothing


getAddToTableGroupingPanelConfig :
    Config msg
    -> StateForGroupingPanel msg
    -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
getAddToTableGroupingPanelConfig config ({ clearAllMsg, clearItemMsg, groupingSelectedMsg, activeGrouping, items, warning, attributesLoading, model } as params) =
    let
        itemsCount =
            List.length items

        addingItemsCount =
            if activeGrouping == Split then
                itemsCount

            else
                1

        addBtnPrefix =
            "Add " ++ String.fromInt addingItemsCount ++ " "

        insertToTableMsg direction =
            items
                |> config.addItemsToTable direction activeGrouping

        containsAverage : Bool
        containsAverage =
            List.any isSelectedAverage items

        containsMoreThanSingleGroup : Bool
        containsMoreThanSingleGroup =
            List.any isSelectedGroup items && (List.length items > 1)

        containsSingleGroup : Bool
        containsSingleGroup =
            List.any isSelectedGroup items && (List.length items == 1)

        isGroupingMode : Bool
        isGroupingMode =
            (UndoRedo.current model |> .groupingItemWith) /= Nothing

        activeGrouping_ : Grouping
        activeGrouping_ =
            if containsSingleGroup then
                List.head items
                    |> Maybe.andThen getGroupingFromItem
                    |> Maybe.withDefault activeGrouping

            else
                activeGrouping

        cnf =
            { title = "Add to your crosstab"
            , placeholder =
                \num ->
                    if num == 0 then
                        Just
                            [ ( GroupingPanel.Plain, "Add one or more " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            , ( GroupingPanel.Plain, " to start querying" )
                            ]

                    else if num > 0 && num < 4 then
                        Just
                            [ ( GroupingPanel.Plain, "Continue adding " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            ]

                    else
                        Nothing
            , placeholderIcon = P2Icons.groupingPanelPlaceholderXB
            , activeGrouping = activeGrouping_
            , isClearable = True
            , isLoading = attributesLoading
            , warning = warningView warning
            , groupings =
                [ ( Split, 1 ), ( And, 2 ), ( Or, 2 ) ]
                    |> List.map
                        (\( grouping, minimumItemCountToBeEnabled ) ->
                            { grouping = grouping
                            , disabled =
                                if containsMoreThanSingleGroup || isGroupingMode then
                                    True

                                else if containsAverage then
                                    grouping /= Split

                                else if containsSingleGroup then
                                    False

                                else
                                    itemsCount < minimumItemCountToBeEnabled
                            , onClick = groupingSelectedMsg grouping
                            }
                        )
            , items = itemsForGroupingPanel items
            , buttons =
                [ { label = addBtnPrefix ++ XB2.Share.Plural.fromInt addingItemsCount "row"
                  , onClick = insertToTableMsg Row
                  , disabled = addingItemsCount == 0
                  }
                , { label = addBtnPrefix ++ XB2.Share.Plural.fromInt addingItemsCount "column"
                  , onClick = insertToTableMsg Column
                  , disabled = addingItemsCount == 0
                  }
                ]
            , clearAll = clearAllMsg
            , clearItem = clearItemMsg
            , undo = params.undoMsg
            , redo = params.redoMsg
            , canUndo = params.canUndo
            , canRedo = params.canRedo
            }
    in
    toComplexExpressionPanelConfig config [ Split, And, Or ] params cnf


getMetadataNotesViewConfig :
    Config msg
    -> StateForGroupingPanel msg
    -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
getMetadataNotesViewConfig config ({ clearAllMsg, clearItemMsg, groupingSelectedMsg, activeGrouping, items, warning, attributesLoading, model } as params) =
    let
        itemsCount =
            List.length items

        addingItemsCount =
            if activeGrouping == Split then
                itemsCount

            else
                1

        addBtnPrefix =
            "Add " ++ String.fromInt addingItemsCount ++ " "

        insertToTableMsg direction =
            items
                |> config.addItemsToTable direction activeGrouping

        containsAverage : Bool
        containsAverage =
            List.any isSelectedAverage items

        containsMoreThanSingleGroup : Bool
        containsMoreThanSingleGroup =
            List.any isSelectedGroup items && (List.length items > 1)

        containsSingleGroup : Bool
        containsSingleGroup =
            List.any isSelectedGroup items && (List.length items == 1)

        isGroupingMode : Bool
        isGroupingMode =
            (UndoRedo.current model |> .groupingItemWith) /= Nothing

        activeGrouping_ : Grouping
        activeGrouping_ =
            if containsSingleGroup then
                List.head items
                    |> Maybe.andThen getGroupingFromItem
                    |> Maybe.withDefault activeGrouping

            else
                activeGrouping

        cnf =
            { title = "Add to your crosstab"
            , placeholder =
                \num ->
                    if num == 0 then
                        Just
                            [ ( GroupingPanel.Plain, "Add one or more " )
                            , ( GroupingPanel.Bold, "attributes from the same" )
                            , ( GroupingPanel.Plain, " question" )
                            ]

                    else if num > 0 && num < 4 then
                        Just
                            [ ( GroupingPanel.Plain, "Continue adding " )
                            , ( GroupingPanel.Bold, "attributes" )
                            ]

                    else
                        Nothing
            , placeholderIcon = P2Icons.groupingPanelPlaceholderXB
            , activeGrouping = activeGrouping_
            , isClearable = True
            , isLoading = attributesLoading
            , warning = warningView warning
            , groupings =
                [ ( Split, 1 ), ( And, 2 ), ( Or, 2 ) ]
                    |> List.map
                        (\( grouping, minimumItemCountToBeEnabled ) ->
                            { grouping = grouping
                            , disabled =
                                if containsMoreThanSingleGroup || isGroupingMode then
                                    True

                                else if containsAverage then
                                    grouping /= Split

                                else if containsSingleGroup then
                                    False

                                else
                                    itemsCount < minimumItemCountToBeEnabled
                            , onClick = groupingSelectedMsg grouping
                            }
                        )
            , items = itemsForGroupingPanel items
            , buttons =
                [ { label = addBtnPrefix ++ XB2.Share.Plural.fromInt addingItemsCount "row"
                  , onClick = insertToTableMsg Row
                  , disabled = addingItemsCount == 0
                  }
                , { label = addBtnPrefix ++ XB2.Share.Plural.fromInt addingItemsCount "column"
                  , onClick = insertToTableMsg Column
                  , disabled = addingItemsCount == 0
                  }
                ]
            , clearAll = clearAllMsg
            , clearItem = clearItemMsg
            , undo = params.undoMsg
            , redo = params.redoMsg
            , canUndo = params.canUndo
            , canRedo = params.canRedo
            }
    in
    toComplexExpressionPanelConfig config [ Split, And, Or ] params cnf


getAffixToTableGroupingPanelConfig :
    Config msg
    -> StateForGroupingPanel msg
    -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
getAffixToTableGroupingPanelConfig config ({ clearAllMsg, clearItemMsg, groupingSelectedMsg, items, warning, attributesLoading } as params) =
    let
        activeGrouping =
            if params.activeGrouping == Split then
                And

            else
                params.activeGrouping

        insertToTableMsg logicOperator =
            items
                |> config.viewAffixModalFromAttrBrowser logicOperator activeGrouping params.affixedFrom

        cnf =
            { title = "Affix to expression"
            , placeholder =
                \num ->
                    if num == 0 then
                        Just
                            [ ( GroupingPanel.Plain, "Add one or more " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            , ( GroupingPanel.Plain, " to start querying" )
                            ]

                    else if num > 0 && num < 4 then
                        Just
                            [ ( GroupingPanel.Plain, "Continue adding " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            ]

                    else
                        Nothing
            , placeholderIcon = P2Icons.groupingPanelPlaceholderXB
            , activeGrouping = activeGrouping
            , isClearable = True
            , isLoading = attributesLoading
            , warning = warningView warning
            , groupings =
                [ And, Or ]
                    |> List.map
                        (\grouping ->
                            { grouping = grouping
                            , disabled = List.length items < 2
                            , onClick = groupingSelectedMsg grouping
                            }
                        )
            , items = itemsForGroupingPanel items
            , buttons =
                [ { label = "Affix with AND"
                  , onClick = insertToTableMsg Expression.And
                  , disabled = List.isEmpty items
                  }
                , { label = "Affix with OR"
                  , onClick = insertToTableMsg Expression.Or
                  , disabled = List.isEmpty items
                  }
                ]
            , clearAll = clearAllMsg
            , clearItem = clearItemMsg
            , undo = params.undoMsg
            , redo = params.redoMsg
            , canUndo = params.canUndo
            , canRedo = params.canRedo
            }
    in
    toComplexExpressionPanelConfig config [ And, Or ] params cnf


getEditToTableGroupingPanelConfig :
    Config msg
    -> StateForGroupingPanel msg
    -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
getEditToTableGroupingPanelConfig config ({ clearAllMsg, clearItemMsg, groupingSelectedMsg, items, warning, attributesLoading } as params) =
    let
        activeGrouping =
            if params.activeGrouping == Split then
                And

            else
                params.activeGrouping

        insertToTableMsg =
            items
                |> config.viewEditModalFromAttrBrowser activeGrouping

        cnf =
            { title = "Edit expression"
            , placeholder =
                \num ->
                    if num == 0 then
                        Just
                            [ ( GroupingPanel.Plain, "Add one or more " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            , ( GroupingPanel.Plain, " to start querying" )
                            ]

                    else
                        Nothing
            , placeholderIcon = P2Icons.groupingPanelPlaceholderXB
            , activeGrouping = activeGrouping
            , isClearable = True
            , isLoading = attributesLoading
            , warning = warningView warning
            , groupings =
                [ And, Or ]
                    |> List.map
                        (\grouping ->
                            { grouping = grouping
                            , disabled = List.length items < 2
                            , onClick = groupingSelectedMsg grouping
                            }
                        )
            , items = itemsForGroupingPanel items
            , buttons =
                [ { label = "Apply"
                  , onClick = insertToTableMsg
                  , disabled = List.isEmpty items || params.originalItemsBeforeEditing == items
                  }
                ]
            , clearAll = clearAllMsg
            , clearItem = clearItemMsg
            , undo = params.undoMsg
            , redo = params.redoMsg
            , canUndo = params.canUndo
            , canRedo = params.canRedo
            }
    in
    toComplexExpressionPanelConfig config [ And, Or ] params cnf


getAddBaseGroupingPanelConfig :
    Config msg
    -> StateForGroupingPanel msg
    -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
getAddBaseGroupingPanelConfig config ({ clearAllMsg, clearItemMsg, groupingSelectedMsg, items, activeGrouping, warning, model, attributesLoading } as params) =
    let
        itemsCount =
            List.length items

        addingItemsCount =
            if activeGrouping == Split then
                itemsCount

            else
                1

        insertToTableMsg =
            items
                |> config.addBaseAudiences activeGrouping

        containsAverage : Bool
        containsAverage =
            List.any isSelectedAverage items

        containsMoreThanSingleGroup : Bool
        containsMoreThanSingleGroup =
            List.any isSelectedGroup items && (List.length items > 1)

        containsSingleGroup : Bool
        containsSingleGroup =
            List.any isSelectedGroup items && (List.length items == 1)

        isGroupingMode : Bool
        isGroupingMode =
            (UndoRedo.current model |> .groupingItemWith) /= Nothing

        activeGrouping_ : Grouping
        activeGrouping_ =
            if containsSingleGroup then
                List.head items
                    |> Maybe.andThen getGroupingFromItem
                    |> Maybe.withDefault activeGrouping

            else
                activeGrouping

        cnf =
            { title = "Create a new base"
            , placeholder =
                \num ->
                    if num == 0 then
                        Just
                            [ ( GroupingPanel.Plain, "Add one or more " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            , ( GroupingPanel.Plain, " to create base audiences" )
                            ]

                    else if num > 0 && num < 4 then
                        Just
                            [ ( GroupingPanel.Plain, "Continue adding " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            ]

                    else
                        Nothing
            , placeholderIcon = P2Icons.groupingPanelPlaceholderXB
            , activeGrouping = activeGrouping_
            , isClearable = True
            , isLoading = attributesLoading
            , warning = warningView warning
            , groupings =
                [ ( Split, 1 ), ( And, 2 ), ( Or, 2 ) ]
                    |> List.map
                        (\( grouping, minimumItemCountToBeEnabled ) ->
                            { grouping = grouping
                            , disabled =
                                if containsMoreThanSingleGroup || isGroupingMode then
                                    True

                                else if containsAverage then
                                    grouping /= Split

                                else if containsSingleGroup then
                                    False

                                else
                                    itemsCount < minimumItemCountToBeEnabled
                            , onClick = groupingSelectedMsg grouping
                            }
                        )
            , items = itemsForGroupingPanel items
            , buttons =
                [ { label = "Apply " ++ String.fromInt addingItemsCount ++ XB2.Share.Plural.fromInt addingItemsCount " base"
                  , onClick = insertToTableMsg
                  , disabled = List.isEmpty items
                  }
                ]
            , clearAll = clearAllMsg
            , clearItem = clearItemMsg
            , undo = params.undoMsg
            , redo = params.redoMsg
            , canUndo = params.canUndo
            , canRedo = params.canRedo
            }
    in
    toComplexExpressionPanelConfig config [ Split, And, Or ] params cnf


getAffixBaseGroupingPanelConfig :
    Config msg
    -> StateForGroupingPanel msg
    -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
getAffixBaseGroupingPanelConfig config ({ clearAllMsg, clearItemMsg, groupingSelectedMsg, items, selectedBasesCount, warning, attributesLoading } as params) =
    let
        activeGrouping =
            if params.activeGrouping == Split then
                And

            else
                params.activeGrouping

        insertToTableMsg logicOperator =
            items
                |> config.viewAffixModalFromAttrBrowser logicOperator activeGrouping params.affixedFrom

        cnf =
            { title = XB2.Share.Plural.fromInt selectedBasesCount "Affix to your base"
            , placeholder =
                \num ->
                    if num == 0 then
                        Just
                            [ ( GroupingPanel.Plain, "Add one or more " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            , ( GroupingPanel.Plain, " to create base audiences" )
                            ]

                    else if num > 0 && num < 4 then
                        Just
                            [ ( GroupingPanel.Plain, "Continue adding " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            ]

                    else
                        Nothing
            , placeholderIcon = P2Icons.groupingPanelPlaceholderXB
            , activeGrouping = activeGrouping
            , isClearable = True
            , isLoading = attributesLoading
            , warning = warningView warning
            , groupings =
                [ And, Or ]
                    |> List.map
                        (\grouping ->
                            { grouping = grouping
                            , disabled = List.length items < 2
                            , onClick = groupingSelectedMsg grouping
                            }
                        )
            , items = itemsForGroupingPanel items
            , buttons =
                [ { label = "Affix with AND"
                  , onClick = insertToTableMsg Expression.And
                  , disabled = List.isEmpty items
                  }
                , { label = "Affix with OR"
                  , onClick = insertToTableMsg Expression.Or
                  , disabled = List.isEmpty items
                  }
                ]
            , clearAll = clearAllMsg
            , clearItem = clearItemMsg
            , undo = params.undoMsg
            , redo = params.redoMsg
            , canUndo = params.canUndo
            , canRedo = params.canRedo
            }
    in
    toComplexExpressionPanelConfig config [ And, Or ] params cnf


getEditBaseGroupingPanelConfig :
    Config msg
    -> StateForGroupingPanel msg
    -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
getEditBaseGroupingPanelConfig config ({ clearAllMsg, clearItemMsg, groupingSelectedMsg, items, warning, attributesLoading } as params) =
    let
        activeGrouping =
            if params.activeGrouping == Split then
                And

            else
                params.activeGrouping

        insertToTableMsg =
            items
                |> config.viewEditModalFromAttrBrowser activeGrouping

        cnf =
            { title = "Edit base expression"
            , placeholder =
                \num ->
                    if num == 0 then
                        Just
                            [ ( GroupingPanel.Plain, "Add one or more " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            , ( GroupingPanel.Plain, " to start editing your base audience" )
                            ]

                    else
                        Nothing
            , placeholderIcon = P2Icons.groupingPanelPlaceholderXB
            , activeGrouping = activeGrouping
            , isClearable = True
            , isLoading = attributesLoading
            , warning = warningView warning
            , groupings =
                [ And, Or ]
                    |> List.map
                        (\grouping ->
                            { grouping = grouping
                            , disabled = List.length items < 2
                            , onClick = groupingSelectedMsg grouping
                            }
                        )
            , items = itemsForGroupingPanel items
            , buttons =
                [ { label = "Apply"
                  , onClick = insertToTableMsg
                  , disabled = List.isEmpty items || params.originalItemsBeforeEditing == items
                  }
                ]
            , clearAll = clearAllMsg
            , clearItem = clearItemMsg
            , undo = params.undoMsg
            , redo = params.redoMsg
            , canUndo = params.canUndo
            , canRedo = params.canRedo
            }
    in
    toComplexExpressionPanelConfig config [ And, Or ] params cnf


getReplaceBaseGroupingPanelConfig :
    Config msg
    -> StateForGroupingPanel msg
    -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
getReplaceBaseGroupingPanelConfig config ({ clearAllMsg, clearItemMsg, groupingSelectedMsg, items, warning, attributesLoading } as params) =
    let
        activeGrouping =
            if params.activeGrouping == Split then
                And

            else
                params.activeGrouping

        insertToTableMsg =
            items
                |> config.replaceDefaultBase activeGrouping

        cnf =
            { title = "Replace your default base"
            , placeholder =
                \num ->
                    if num == 0 then
                        Just
                            [ ( GroupingPanel.Plain, "Add one or more " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            , ( GroupingPanel.Plain, " to create base audiences" )
                            ]

                    else if num > 0 && num < 4 then
                        Just
                            [ ( GroupingPanel.Plain, "Continue adding " )
                            , ( GroupingPanel.Bold, "attributes and audiences" )
                            ]

                    else
                        Nothing
            , placeholderIcon = P2Icons.groupingPanelPlaceholderXB
            , activeGrouping = activeGrouping
            , isClearable = True
            , isLoading = attributesLoading
            , warning = warningView warning
            , groupings =
                [ And, Or ]
                    |> List.map
                        (\grouping ->
                            { grouping = grouping
                            , disabled = List.length items < 2
                            , onClick = groupingSelectedMsg grouping
                            }
                        )
            , items = itemsForGroupingPanel items
            , buttons =
                [ { label = "Apply base"
                  , onClick = insertToTableMsg
                  , disabled = List.isEmpty items
                  }
                ]
            , clearAll = clearAllMsg
            , clearItem = clearItemMsg
            , undo = params.undoMsg
            , redo = params.redoMsg
            , canUndo = params.canUndo
            , canRedo = params.canRedo
            }
    in
    toComplexExpressionPanelConfig config [ And, Or ] params cnf


ghostView : ClassName -> DnDModel -> Html Msg
ghostView complexExpressionsPanelClass dnd =
    case dndSystem.info dnd.list of
        Just { dragItem } ->
            Html.div
                (WeakCss.nest "ghost-item" complexExpressionsPanelClass :: dndSystem.ghostStyles dnd)
                [ Html.div [ WeakCss.nestMany [ "ghost-item", "text" ] complexExpressionsPanelClass ] [ Html.text dragItem.title ]
                ]

        Nothing ->
            Html.nothing


{-| TODO: Too many arguments here, use a record
-}
view :
    (Config msg
     -> StateForGroupingPanel msg
     -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
    )
    -> Analytics.AffixedFrom
    -> Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
view getGroupingPanelConfig affixedFrom flags config moduleClass selectedBasesCount canUseAverage datasets datasetsToNamespaces lineages waves locations attributeBrowserInitialState shouldPassInitialStateToAttributeBrowser audienceFolders affixingItems model =
    let
        usedNamespaceCodes : List Namespace.Code
        usedNamespaceCodes =
            affixingItemsNamespaceCodes affixingItems

        compatibleNamespaceCodes : WebData (Set.Any.AnySet Namespace.StringifiedCode Namespace.Code)
        compatibleNamespaceCodes =
            XB2.Share.Data.Labels.compatibleNamespacesWithAll lineages usedNamespaceCodes

        compatibleDatasets : List Dataset
        compatibleDatasets =
            compatibleNamespaceCodes
                |> RemoteData.andThen
                    (\compatibles ->
                        compatibles
                            |> Set.Any.toList
                            |> List.map (XB2.Share.Data.Platform2.datasetsForNamespace datasetsToNamespaces lineages)
                            |> -- questionable
                               List.filter ((/=) NotAsked)
                            |> List.combineRemoteData
                    )
                |> RemoteData.map
                    (List.foldl Set.Any.union XB2.Share.Data.Id.emptySet
                        >> Set.Any.toList
                    )
                |> RemoteData.withDefault []
                |> List.filterMap (\code -> Dict.Any.get code datasets)

        ( selectedAttributes, selectedAudiences, selectedAverages ) =
            UndoRedo.current model
                |> .selectedItems
                |> List.foldr
                    (\item ( attrs, audiences, averages ) ->
                        case item of
                            SelectedAttribute attribute ->
                                ( attribute :: attrs, audiences, averages )

                            SelectedAudience audience ->
                                ( attrs, audience :: audiences, averages )

                            SelectedAverage avg ->
                                ( attrs, audiences, avg :: averages )

                            SelectedGroup group ->
                                ( getAttributesFromGroup group ++ attrs, getAudiencesFromGroup group ++ audiences, averages )
                    )
                    ( [], [], [] )

        attributeBrowserConfig =
            { noOp = config.noOp
            , toggleAttributes = config.msg << ToggleAttributes
            , addAttributes = config.msg << AddAttributes
            , loadingAttributes = config.msg << LoadingAttributes
            , toggleAverage = config.msg << ToggleAverage
            , setDecodingError = config.msg << SetDecodingError
            , warningNoteOpened = config.msg << IncompatibilityWarningNoteOpened
            , gotStateSnapshot = config.gotAttributeBrowserStateSnapshot
            , waves = waves
            , locations = locations
            , activeWaves = UndoRedo.current model |> .activeWaves
            , activeLocations = UndoRedo.current model |> .activeLocations
            , canUseAverage = canUseAverage
            , selectedAttributes = selectedAttributes
            , selectedAverages = selectedAverages
            , selectedDatasets = compatibleDatasets
            , prerequestedAttribute = Nothing
            }

        audienceBrowserConfig =
            { toggleAudience = config.msg << ToggleItem << SelectedAudience
            , showDisabledWarning = config.msg ShowDisabledWarningInAB
            , createAudience = config.createAudience
            , editAudience = config.editAudience
            , preexistingAudiences = []
            , stagedAudiences = selectedAudiences
            , isBase = False
            , setDecodingError = config.msg << SetDecodingError
            , compatibleNamespaces =
                compatibleNamespaceCodes
                    |> RemoteData.map Set.Any.toList
                    |> RemoteData.withDefault []
            , allDatasets = Dict.Any.values datasets
            , appName = "CrosstabBuilder"
            , hideMyAudiencesTab = False
            }

        attributesGroupingPanelConfig : SelectedItems -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
        attributesGroupingPanelConfig items =
            let
                itemsCount =
                    List.length items

                activeGrouping =
                    if itemsCount <= 1 then
                        Split

                    else
                        UndoRedo.current model |> .activeGrouping
            in
            getGroupingPanelConfig config
                { clearAllMsg = config.msg ClearAll
                , clearItemMsg = config.msg << ToggleItem
                , isAffixing = affixingItems /= NotAffixingOrEditing
                , originalItemsBeforeEditing = UndoRedo.current model |> .originalSelectedItemsBeforeEditing
                , groupingSelectedMsg =
                    if affixingItems == NotAffixingOrEditing then
                        config.msg << ComplexMainGroupingSelected

                    else
                        config.msg << GroupingSelected
                , activeGrouping = activeGrouping
                , items = items
                , selectedBasesCount = selectedBasesCount
                , warning = UndoRedo.current model |> .groupingPanelWarning
                , affixedFrom = affixedFrom
                , attributesLoading = UndoRedo.current model |> .attributeBrowserLoadingAttributes
                , model = model
                , undoMsg = config.msg UndoChangesInAttributeBrowser
                , redoMsg = config.msg RedoChangesInAttributeBrowser
                , canUndo = UndoRedo.hasPast model
                , canRedo = UndoRedo.hasFuture model
                }

        complexExpressionsPanelClass =
            moduleClass |> WeakCss.addMany [ "attribute-browser", "complex-grouping-panel" ]

        warningsView : NonEmpty AttributeBrowser.Warning -> Html msg
        warningsView =
            NonemptyList.toList
                >> List.fastConcatMap
                    (\warning ->
                        if List.isEmpty warning.waveNames then
                            [ ( "any of your selected waves", warning.locationsText ) ]

                        else
                            warning.waveNames
                                |> List.map (\w -> ( w, warning.locationsText ))
                    )
                >> List.groupBy Tuple.first
                >> List.map
                    (\{ key, items } ->
                        let
                            locs : List String
                            locs =
                                items
                                    |> NonemptyList.map Tuple.second
                                    |> NonemptyList.toList
                                    |> Maybe.values
                        in
                        Html.div []
                            [ Html.text "- Not asked in "
                            , Html.strong [] [ Html.text key ]
                            , Html.text " in:"
                            , Html.div
                                [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "list", "item" ] moduleClass ]
                                [ Html.strong [] [ Html.text <| String.join ", " locs ] ]
                            ]
                    )
                >> Html.div [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "list" ] moduleClass ]

        groupOrWarningView : Html msg
        groupOrWarningView =
            case UndoRedo.current model |> .incompatibilityWarningNote of
                Just note ->
                    Html.div [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning" ] moduleClass ]
                        [ Html.button
                            [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "close" ] moduleClass
                            , Events.onClick <| config.msg CloseIncompatibilityWarningNote
                            ]
                            [ XB2.Share.Icons.icon [] P2Icons.cross
                            ]
                        , Html.h3 [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "header" ] moduleClass ]
                            [ Html.span [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "header", "icon" ] moduleClass ]
                                [ XB2.Share.Icons.icon [] P2Icons.warning ]
                            , Html.text note.title
                            ]
                        , Html.p [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "disclaimer" ] moduleClass ]
                            [ Html.text "The below warning means that your specific combination of attributes was not asked in certain waves and locations, however the data "
                            , Html.strong [] [ Html.text "is still valid" ]
                            , Html.text "."
                            ]
                        , Html.viewMaybe warningsView note.warnings
                        ]

                Nothing ->
                    let
                        loadingLineages : Bool
                        loadingLineages =
                            lineages
                                |> Dict.Any.values
                                |> List.any RemoteData.isLoading
                    in
                    if loadingLineages then
                        Html.div [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "spinner" ] moduleClass ] [ XB2.Share.Spinner.view ]

                    else
                        XB2GroupingPanel.view (Tuple.first <| attributesGroupingPanelConfig (UndoRedo.current model |> .selectedItems)) complexExpressionsPanelClass
    in
    [ Html.div
        [ WeakCss.nest "attribute-browser" moduleClass ]
        [ P2Modals.headerWithTabsView
            config.closeModal
            (WeakCss.add "general-modal" moduleClass)
            [ { title = "Attributes"
              , active = (UndoRedo.current model |> .activeTab) == AttributesTab
              , icon = P2Icons.attribute
              , onClick = Just <| config.msg <| SetActiveTab AttributesTab
              }
            , { title = "Audiences"
              , active = (UndoRedo.current model |> .activeTab) == AudiencesTab
              , icon = P2Icons.audiences
              , onClick = Just <| config.msg <| SetActiveTab AudiencesTab
              }
            ]
        , Html.div
            [ WeakCss.nestMany [ "attribute-browser", "content" ] moduleClass ]
            [ Html.div
                [ WeakCss.nestMany [ "attribute-browser", "content", "left-part" ] moduleClass ]
                [ Html.div
                    [ WeakCss.addMany [ "attribute-browser", "content", "left-part", "attributes" ] moduleClass
                        |> WeakCss.withStates [ ( "visible", (UndoRedo.current model |> .activeTab) == AttributesTab ) ]
                    ]
                    [ AttributeBrowser.view flags
                        attributeBrowserConfig
                        attributeBrowserInitialState
                        shouldPassInitialStateToAttributeBrowser
                    ]
                , Html.div
                    [ WeakCss.addMany [ "attribute-browser", "content", "left-part", "audiences" ] moduleClass
                        |> WeakCss.withStates [ ( "visible", (UndoRedo.current model |> .activeTab) == AudiencesTab ) ]
                    ]
                    [ AudienceBrowser.view
                        flags
                        audienceBrowserConfig
                        audienceFolders
                    ]
                ]
            , Html.div
                [ WeakCss.addMany [ "attribute-browser", "content", "right-part" ] moduleClass
                    |> WeakCss.withStates [ ( "dragging", Maybe.isJust <| dndSystem.info (UndoRedo.current model |> .dnd |> .list) ) ]
                ]
                [ groupOrWarningView
                , Html.Lazy.lazy2 ghostView
                    complexExpressionsPanelClass
                    (UndoRedo.current model |> .dnd)
                    |> Html.map config.msg
                ]
            , UndoRedo.current model
                |> .errorMessage
                |> Html.viewMaybe
                    (\err ->
                        Html.div
                            [ WeakCss.nestMany [ "attribute-browser", "content", "error-view" ] moduleClass ]
                            [ Html.text err ]
                    )
            ]
        ]
    , Html.viewMaybe DropdownMenu.view (UndoRedo.current model |> .activeDropdown)
        |> Html.map config.msg
    ]


{-| TODO: Too many arguments here, use a record
-}
viewMetadataModal :
    (Config msg
     -> StateForGroupingPanel msg
     -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
    )
    -> Analytics.AffixedFrom
    -> Maybe Attribute
    -> Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
viewMetadataModal getGroupingPanelConfig affixedFrom prerequestedAttribute flags config moduleClass selectedBasesCount canUseAverage datasets datasetsToNamespaces lineages waves locations attributeBrowserInitialState shouldPassInitialStateToAttributeBrowser audienceFolders affixingItems model =
    let
        usedNamespaceCodes : List Namespace.Code
        usedNamespaceCodes =
            affixingItemsNamespaceCodes affixingItems

        compatibleNamespaceCodes : WebData (Set.Any.AnySet Namespace.StringifiedCode Namespace.Code)
        compatibleNamespaceCodes =
            XB2.Share.Data.Labels.compatibleNamespacesWithAll lineages usedNamespaceCodes

        compatibleDatasets : List Dataset
        compatibleDatasets =
            compatibleNamespaceCodes
                |> RemoteData.andThen
                    (\compatibles ->
                        compatibles
                            |> Set.Any.toList
                            |> List.map (XB2.Share.Data.Platform2.datasetsForNamespace datasetsToNamespaces lineages)
                            |> -- questionable
                               List.filter ((/=) NotAsked)
                            |> List.combineRemoteData
                    )
                |> RemoteData.map
                    (List.foldl Set.Any.union XB2.Share.Data.Id.emptySet
                        >> Set.Any.toList
                    )
                |> RemoteData.withDefault []
                |> List.filterMap (\code -> Dict.Any.get code datasets)

        ( selectedAttributes, selectedAudiences, selectedAverages ) =
            UndoRedo.current model
                |> .selectedItems
                |> List.foldr
                    (\item ( attrs, audiences, averages ) ->
                        case item of
                            SelectedAttribute attribute ->
                                ( attribute :: attrs, audiences, averages )

                            SelectedAudience audience ->
                                ( attrs, audience :: audiences, averages )

                            SelectedAverage avg ->
                                ( attrs, audiences, avg :: averages )

                            SelectedGroup group ->
                                ( getAttributesFromGroup group ++ attrs, getAudiencesFromGroup group ++ audiences, averages )
                    )
                    ( [], [], [] )

        attributeBrowserConfig =
            { noOp = config.noOp
            , toggleAttributes = config.msg << ToggleAttributes
            , addAttributes = config.msg << AddAttributes
            , loadingAttributes = config.msg << LoadingAttributes
            , toggleAverage = config.msg << ToggleAverage
            , setDecodingError = config.msg << SetDecodingError
            , warningNoteOpened = config.msg << IncompatibilityWarningNoteOpened
            , gotStateSnapshot = config.gotAttributeBrowserStateSnapshot
            , waves = waves
            , locations = locations
            , activeWaves = UndoRedo.current model |> .activeWaves
            , activeLocations = UndoRedo.current model |> .activeLocations
            , canUseAverage = canUseAverage
            , selectedAttributes = selectedAttributes
            , selectedAverages = selectedAverages
            , selectedDatasets = compatibleDatasets
            , prerequestedAttribute = prerequestedAttribute
            }

        audienceBrowserConfig =
            { toggleAudience = config.msg << ToggleItem << SelectedAudience
            , showDisabledWarning = config.msg ShowDisabledWarningInAB
            , createAudience = config.createAudience
            , editAudience = config.editAudience
            , preexistingAudiences = []
            , stagedAudiences = selectedAudiences
            , isBase = False
            , setDecodingError = config.msg << SetDecodingError
            , compatibleNamespaces =
                compatibleNamespaceCodes
                    |> RemoteData.map Set.Any.toList
                    |> RemoteData.withDefault []
            , allDatasets = Dict.Any.values datasets
            , appName = "CrosstabBuilder"
            , hideMyAudiencesTab = False
            }

        attributesGroupingPanelConfig : SelectedItems -> ( XB2GroupingPanel.Config SelectedItem msg, GroupingPanel.Config SelectedItem msg )
        attributesGroupingPanelConfig items =
            let
                itemsCount =
                    List.length items

                activeGrouping =
                    if itemsCount <= 1 then
                        Split

                    else
                        UndoRedo.current model |> .activeGrouping
            in
            getGroupingPanelConfig config
                { clearAllMsg = config.msg ClearAll
                , clearItemMsg = config.msg << ToggleItem
                , isAffixing = affixingItems /= NotAffixingOrEditing
                , originalItemsBeforeEditing = UndoRedo.current model |> .originalSelectedItemsBeforeEditing
                , groupingSelectedMsg =
                    if affixingItems == NotAffixingOrEditing then
                        config.msg << ComplexMainGroupingSelected

                    else
                        config.msg << GroupingSelected
                , activeGrouping = activeGrouping
                , items = items
                , selectedBasesCount = selectedBasesCount
                , warning = UndoRedo.current model |> .groupingPanelWarning
                , affixedFrom = affixedFrom
                , attributesLoading = UndoRedo.current model |> .attributeBrowserLoadingAttributes
                , model = model
                , undoMsg = config.msg UndoChangesInAttributeBrowser
                , redoMsg = config.msg RedoChangesInAttributeBrowser
                , canUndo = UndoRedo.hasPast model
                , canRedo = UndoRedo.hasFuture model
                }

        complexExpressionsPanelClass =
            moduleClass |> WeakCss.addMany [ "attribute-browser", "complex-grouping-panel" ]

        warningsView : NonEmpty AttributeBrowser.Warning -> Html msg
        warningsView =
            NonemptyList.toList
                >> List.fastConcatMap
                    (\warning ->
                        if List.isEmpty warning.waveNames then
                            [ ( "any of your selected waves", warning.locationsText ) ]

                        else
                            warning.waveNames
                                |> List.map (\w -> ( w, warning.locationsText ))
                    )
                >> List.groupBy Tuple.first
                >> List.map
                    (\{ key, items } ->
                        let
                            locs : List String
                            locs =
                                items
                                    |> NonemptyList.map Tuple.second
                                    |> NonemptyList.toList
                                    |> Maybe.values
                        in
                        Html.div []
                            [ Html.text "- Not asked in "
                            , Html.strong [] [ Html.text key ]
                            , Html.text " in:"
                            , Html.div
                                [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "list", "item" ] moduleClass ]
                                [ Html.strong [] [ Html.text <| String.join ", " locs ] ]
                            ]
                    )
                >> Html.div [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "list" ] moduleClass ]

        groupOrWarningView : Html msg
        groupOrWarningView =
            case UndoRedo.current model |> .incompatibilityWarningNote of
                Just note ->
                    Html.div [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning" ] moduleClass ]
                        [ Html.button
                            [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "close" ] moduleClass
                            , Events.onClick <| config.msg CloseIncompatibilityWarningNote
                            ]
                            [ XB2.Share.Icons.icon [] P2Icons.cross
                            ]
                        , Html.h3 [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "header" ] moduleClass ]
                            [ Html.span [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "header", "icon" ] moduleClass ]
                                [ XB2.Share.Icons.icon [] P2Icons.warning ]
                            , Html.text note.title
                            ]
                        , Html.p [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "warning", "disclaimer" ] moduleClass ]
                            [ Html.text "The below warning means that your specific combination of attributes was not asked in certain waves and locations, however the data "
                            , Html.strong [] [ Html.text "is still valid" ]
                            , Html.text "."
                            ]
                        , Html.viewMaybe warningsView note.warnings
                        ]

                Nothing ->
                    let
                        loadingLineages : Bool
                        loadingLineages =
                            lineages
                                |> Dict.Any.values
                                |> List.any RemoteData.isLoading
                    in
                    if loadingLineages then
                        Html.div [ WeakCss.nestMany [ "attribute-browser", "content", "right-part", "spinner" ] moduleClass ] [ XB2.Share.Spinner.view ]

                    else
                        XB2GroupingPanel.view (Tuple.first <| attributesGroupingPanelConfig (UndoRedo.current model |> .selectedItems)) complexExpressionsPanelClass
    in
    [ Html.div
        [ WeakCss.nest "attribute-browser" moduleClass ]
        [ P2Modals.headerWithTabsView
            config.closeModal
            (WeakCss.add "general-modal" moduleClass)
            [ { title = "Metadata"
              , active = True
              , icon = P2Icons.info
              , onClick = Nothing
              }
            ]
        , Html.div
            [ WeakCss.nestMany [ "attribute-browser", "content" ] moduleClass ]
            [ Html.div
                [ WeakCss.nestMany [ "attribute-browser", "content", "left-part" ] moduleClass ]
                [ Html.div
                    [ WeakCss.addMany [ "attribute-browser", "content", "left-part", "attributes" ] moduleClass
                        |> WeakCss.withStates [ ( "visible", (UndoRedo.current model |> .activeTab) == AttributesTab ) ]
                    ]
                    [ AttributeBrowser.view flags
                        attributeBrowserConfig
                        attributeBrowserInitialState
                        shouldPassInitialStateToAttributeBrowser
                    ]
                , Html.div
                    [ WeakCss.addMany [ "attribute-browser", "content", "left-part", "audiences" ] moduleClass
                        |> WeakCss.withStates [ ( "visible", (UndoRedo.current model |> .activeTab) == AudiencesTab ) ]
                    ]
                    [ AudienceBrowser.view
                        flags
                        audienceBrowserConfig
                        audienceFolders
                    ]
                ]
            , Html.div
                [ WeakCss.addMany [ "attribute-browser", "content", "right-part" ] moduleClass
                    |> WeakCss.withStates [ ( "dragging", Maybe.isJust <| dndSystem.info (UndoRedo.current model |> .dnd |> .list) ) ]
                ]
                [ groupOrWarningView
                , Html.Lazy.lazy2 ghostView
                    complexExpressionsPanelClass
                    (UndoRedo.current model |> .dnd)
                    |> Html.map config.msg
                ]
            , UndoRedo.current model
                |> .errorMessage
                |> Html.viewMaybe
                    (\err ->
                        Html.div
                            [ WeakCss.nestMany [ "attribute-browser", "content", "error-view" ] moduleClass ]
                            [ Html.text err ]
                    )
            ]
        ]
    , Html.viewMaybe DropdownMenu.view (UndoRedo.current model |> .activeDropdown)
        |> Html.map config.msg
    ]


{-| TODO: Too many arguments here, use a record
-}
addToTableView :
    Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
addToTableView =
    view getAddToTableGroupingPanelConfig Analytics.NotTracked


{-| TODO: Too many arguments here, use a record
-}
metadataNotesView :
    Attribute
    -> Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
metadataNotesView attribute =
    viewMetadataModal getMetadataNotesViewConfig Analytics.NotTracked (Just attribute)


{-| TODO: Too many arguments here, use a record
-}
affixTableView :
    Analytics.AffixedFrom
    -> Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
affixTableView analytics =
    view getAffixToTableGroupingPanelConfig analytics


{-| TODO: Too many arguments here, use a record
-}
editTableView :
    Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
editTableView =
    view getEditToTableGroupingPanelConfig Analytics.NotTracked


{-| TODO: Too many arguments here, use a record
-}
addBaseView :
    Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
addBaseView =
    view getAddBaseGroupingPanelConfig Analytics.NotTracked


{-| TODO: Too many arguments here, use a record
-}
affixBaseView :
    Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
affixBaseView =
    view getAffixBaseGroupingPanelConfig Analytics.NotTracked


{-| TODO: Too many arguments here, use a record
-}
editBaseView :
    Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
editBaseView =
    view getEditBaseGroupingPanelConfig Analytics.NotTracked


{-| TODO: Too many arguments here, use a record
-}
replaceDefaultBaseView :
    Flags
    -> Config msg
    -> ClassName
    -> Int
    -> Bool
    -> IdDict DatasetCodeTag Dataset
    -> BiDict DatasetCode Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> IdDict WaveCodeTag Wave
    -> IdDict LocationCodeTag Location
    -> String
    -> Bool
    -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
    -> AffixingOrEditingItems
    -> Model
    -> List (Html msg)
replaceDefaultBaseView =
    view getReplaceBaseGroupingPanelConfig Analytics.NotTracked


selectedItemNamespaceCodes : SelectedItem -> List Namespace.Code
selectedItemNamespaceCodes item =
    case item of
        SelectedAttribute attr ->
            [ attr.namespaceCode ]

        SelectedAudience { expression } ->
            Expression.getNamespaceCodes expression

        SelectedAverage avg ->
            case avg of
                AvgWithoutSuffixes { namespaceCode } ->
                    [ namespaceCode ]

                AvgWithSuffixes { namespaceCode } _ ->
                    [ namespaceCode ]

        SelectedGroup group ->
            getAttributesFromGroup group
                |> List.map .namespaceCode


affixingItemsNamespaceCodes : AffixingOrEditingItems -> List Namespace.Code
affixingItemsNamespaceCodes affixingItems =
    case affixingItems of
        NotAffixingOrEditing ->
            []

        AffixingBases bases ->
            bases
                |> NonemptyList.toList
                |> List.fastConcatMap BaseAudience.namespaceCodes

        AffixingRowsOrColumns items ->
            items
                |> NonemptyList.toList
                |> List.fastConcatMap (\( _, key ) -> ACrosstab.keyNamespaceCodes key)

        EditingBases _ ->
            []

        EditingRowsOrColumns _ ->
            []


getSelectedItemQuestionCodes : SelectedItem -> List NamespaceAndQuestionCode
getSelectedItemQuestionCodes item =
    case item of
        SelectedAttribute { codes, namespaceCode } ->
            [ XB2.Share.Data.Labels.addNamespaceToQuestionCode namespaceCode codes.questionCode ]

        SelectedAudience { expression } ->
            Expression.getQuestionCodes expression

        SelectedAverage avg ->
            [ AttributeBrowser.getAverageQuestionCode avg ]

        SelectedGroup group ->
            getAttributesFromGroup group
                |> List.map (\{ codes, namespaceCode } -> XB2.Share.Data.Labels.addNamespaceToQuestionCode namespaceCode codes.questionCode)


subscribeUndoRedoKeyShortcuts : Sub Msg
subscribeUndoRedoKeyShortcuts =
    Browser.Events.onKeyDown
        (Decode.map4
            (\char ctrl meta shift ->
                case ( ctrl, meta, shift ) of
                    ( True, False, False ) ->
                        if char == "z" then
                            UndoChangesInAttributeBrowser

                        else if char == "y" then
                            RedoChangesInAttributeBrowser

                        else
                            NoOp

                    ( False, True, False ) ->
                        if char == "z" then
                            UndoChangesInAttributeBrowser

                        else
                            NoOp

                    ( False, True, True ) ->
                        if char == "z" then
                            RedoChangesInAttributeBrowser

                        else
                            NoOp

                    _ ->
                        NoOp
            )
            (Decode.field "key" Decode.string)
            (Decode.field "ctrlKey" Decode.bool)
            (Decode.field "metaKey" Decode.bool)
            (Decode.field "shiftKey" Decode.bool)
        )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ case UndoRedo.current model |> .activeDropdown of
            Just _ ->
                Browser.Events.onClick <| Decode.succeed CloseDropdown

            Nothing ->
                Sub.none
        , case UndoRedo.current model |> .groupingPanelWarning of
            NoWarning ->
                Sub.none

            WarningVisible _ ->
                Time.every 5000 (always <| CheckWarningState 5000)
        , dndSystem.subscriptions (UndoRedo.current model |> .dnd)
        , subscribeUndoRedoKeyShortcuts
        ]


arePossibleDatasetIncompatibilities : Maybe AudienceCrosstab -> List Namespace.Code -> Bool
arePossibleDatasetIncompatibilities crosstabData selectedNamespaceCodes =
    let
        selected : Set.Any.AnySet Namespace.StringifiedCode Namespace.Code
        selected =
            Set.Any.fromList Namespace.codeToString selectedNamespaceCodes

        audiences : Maybe (List AudienceDefinition)
        audiences =
            Maybe.map2 (++)
                (crosstabData |> Maybe.map (ACrosstab.getRows >> List.map (.item >> XB2.Data.AudienceItem.getDefinition)))
                (crosstabData |> Maybe.map (ACrosstab.getColumns >> List.map (.item >> XB2.Data.AudienceItem.getDefinition)))

        current : Set.Any.AnySet Namespace.StringifiedCode Namespace.Code
        current =
            Maybe.unwrap (Set.Any.empty Namespace.codeToString)
                (List.fastConcatMap XB2.Data.definitionNamespaceCodes >> Set.Any.fromList Namespace.codeToString)
                audiences
    in
    AnySet.areDifferent Namespace.codeToString selected current && not (Set.Any.isEmpty current)


setModalBrowserWarning : Warning -> Model -> Model
setModalBrowserWarning warning model =
    UndoRedo.updateCurrent
        (\m ->
            { m
                | groupingPanelWarning =
                    WarningVisible { warning = warning, msTTL = warningVisiblityTime }
            }
        )
        model


getModalWarning : Model -> Maybe Warning
getModalWarning model =
    case UndoRedo.current model |> .groupingPanelWarning of
        NoWarning ->
            Nothing

        WarningVisible { warning } ->
            Just warning
