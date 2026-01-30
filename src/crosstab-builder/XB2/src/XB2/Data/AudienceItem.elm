module XB2.Data.AudienceItem exposing
    ( AudienceItem
    , fromCaptionAverage
    , fromCaptionDeviceBasedUsage
    , fromCaptionExpression
    , fromSavedProject
    , generateNewId
    , getCaption
    , getDefinition
    , getId
    , getIdString
    , getNamespaceAndQuestionCodes
    , isAverage
    , isAverageOrDbu
    , setCaption
    , setDefinition
    , setExpression
    , toAudienceData
    , totalItem
    )

{-| This module works with the row & column items for an
[`AudienceCrosstab`](XB2.Data.AudienceCrosstab#AudienceCrosstab).
-}

import Random
import XB2.Data as Data
import XB2.Data.Audience.Expression as AudienceExpression
import XB2.Data.AudienceItemId as AudienceItemId
import XB2.Data.Average as Average
import XB2.Data.Caption as Caption
import XB2.Data.DeviceBasedUsage as DeviceBasedUsage
import XB2.Share.Data.Labels as Labels


{-| AudienceItem is the row or column of a crosstab. An AudienceItem definition can
either be an [`Expression`](Data.Audience.Expression#AudienceExpression) or an
[`Average`](XB2.Data.Average#Average).
-}
type AudienceItem
    = AudienceItem
        { id : AudienceItemId.AudienceItemId
        , caption : Caption.Caption
        , definition : Data.AudienceDefinition
        }


totalItem : AudienceItem
totalItem =
    Tuple.first <|
        fromSavedProject
            { id = AudienceItemId.totalString
            , name = "Totals"
            , fullName = "Totals"
            , subtitle = ""
            , definition = Data.Expression AudienceExpression.sizeExpression
            }
            (Random.initialSeed 0)


fromCaptionExpression :
    Random.Seed
    -> Caption.Caption
    -> AudienceExpression.Expression
    -> ( AudienceItem, Random.Seed )
fromCaptionExpression seed caption expression =
    let
        ( id, newSeed ) =
            AudienceItemId.generateId seed
    in
    ( AudienceItem
        { id = id
        , caption = caption
        , definition = Data.Expression expression
        }
    , newSeed
    )


fromCaptionAverage :
    Random.Seed
    -> Caption.Caption
    -> Average.Average
    -> ( AudienceItem, Random.Seed )
fromCaptionAverage seed caption average =
    let
        ( id, newSeed ) =
            AudienceItemId.generateId seed
    in
    ( AudienceItem
        { id = id
        , caption = caption
        , definition = Data.Average average
        }
    , newSeed
    )


fromCaptionDeviceBasedUsage :
    Random.Seed
    -> Caption.Caption
    -> DeviceBasedUsage.DeviceBasedUsage
    -> ( AudienceItem, Random.Seed )
fromCaptionDeviceBasedUsage seed caption dbu =
    let
        ( id, newSeed ) =
            AudienceItemId.generateId seed
    in
    ( AudienceItem
        { id = id
        , caption = caption
        , definition = Data.DeviceBasedUsage dbu
        }
    , newSeed
    )


fromSavedProject : Data.AudienceData -> Random.Seed -> ( AudienceItem, Random.Seed )
fromSavedProject { id, name, subtitle, definition } seed =
    let
        ( itemId, newSeed ) =
            AudienceItemId.generateFromString id seed
    in
    ( AudienceItem
        { id = itemId
        , caption =
            Caption.fromAudience
                { audience = name
                , parent =
                    if String.isEmpty subtitle then
                        Nothing

                    else
                        Just subtitle
                }
        , definition = definition
        }
    , newSeed
    )


generateNewId : AudienceItem -> Random.Seed -> ( AudienceItem, Random.Seed )
generateNewId (AudienceItem data) seed =
    let
        ( itemId, newSeed ) =
            AudienceItemId.generateId seed
    in
    ( AudienceItem { data | id = itemId }, newSeed )


getId : AudienceItem -> AudienceItemId.AudienceItemId
getId (AudienceItem { id }) =
    id


getNamespaceAndQuestionCodes : AudienceItem -> List Labels.NamespaceAndQuestionCode
getNamespaceAndQuestionCodes (AudienceItem { definition }) =
    case definition of
        Data.Expression expression ->
            AudienceExpression.getQuestionCodes expression

        Data.Average average ->
            [ Average.getQuestionCode average ]

        Data.DeviceBasedUsage dbu ->
            [ DeviceBasedUsage.getQuestionCode dbu ]


getIdString : AudienceItem -> String
getIdString =
    AudienceItemId.toString << getId


getCaption : AudienceItem -> Caption.Caption
getCaption (AudienceItem { caption }) =
    caption


getDefinition : AudienceItem -> Data.AudienceDefinition
getDefinition (AudienceItem { definition }) =
    definition


setDefinition : Data.AudienceDefinition -> AudienceItem -> AudienceItem
setDefinition definition (AudienceItem data) =
    AudienceItem { data | definition = definition }


setExpression : AudienceExpression.Expression -> AudienceItem -> AudienceItem
setExpression expression (AudienceItem data) =
    AudienceItem { data | definition = Data.Expression expression }


setCaption : Caption.Caption -> AudienceItem -> AudienceItem
setCaption caption (AudienceItem data) =
    AudienceItem { data | caption = caption }


toAudienceData : AudienceItem -> Data.AudienceData
toAudienceData (AudienceItem data) =
    { id = AudienceItemId.toString data.id
    , name = Caption.getName data.caption
    , fullName = Caption.getFullName data.caption
    , subtitle = Maybe.withDefault "" <| Caption.getSubtitle data.caption
    , definition = data.definition
    }


isAverage : AudienceItem -> Bool
isAverage (AudienceItem { definition }) =
    case definition of
        Data.Expression _ ->
            False

        Data.Average _ ->
            True

        Data.DeviceBasedUsage _ ->
            False


isAverageOrDbu : AudienceItem -> Bool
isAverageOrDbu (AudienceItem { definition }) =
    case definition of
        Data.Expression _ ->
            False

        Data.Average _ ->
            True

        Data.DeviceBasedUsage _ ->
            True
