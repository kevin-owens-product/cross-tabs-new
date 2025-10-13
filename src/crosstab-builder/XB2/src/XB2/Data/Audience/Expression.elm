module XB2.Data.Audience.Expression exposing
    ( Expression(..)
    , ExpressionHelp(..)
    , LeafData
    , LogicOperator(..)
    , allInternetUsersLeafData
    , append
    , decoder
    , encode
    , foldr
    , getNamespaceCodes
    , getQuestionAndDatapointCodes
    , getQuestionCodes
    , intersectionMany
    , sizeExpression
    , unionMany
    )

import Json.Decode as Decode
import Json.Encode as Encode
import List.NonEmpty as NonEmpty
import XB2.Data.Namespace as Namespace
import XB2.Data.Suffix as Suffix
import XB2.Data.Zod.Optional as Optional
import XB2.Share.Data.Id as Id
import XB2.Share.Data.Labels as Labels


{-| Logic operator used for expression interconnections. In layman's terms:

  - _'I want the data of people that has a dog and a cat'_ <- This uses `And` operator
  - _'I want the data of people that has either a dog or a cat'_ <- This uses
    `Or` operator

-}
type LogicOperator
    = -- List of sub-expressions to apply intersection of their scopes
      And
      -- List of sub-expressions to apply union of their scopes
    | Or


logicOperatorToFieldString : LogicOperator -> String
logicOperatorToFieldString logicOperator =
    case logicOperator of
        And ->
            "and"

        Or ->
            "or"


{-| Represents the scope of an `Audience`.

This is an Elm-ish definition of [platform2-react-ui-components](https://github.com/GlobalWebIndex/platform2-react-ui-components/blob/master/src/logic/attributeBrowser/types/models.ts#L93-L104)
`OldExpression`.

-}
type Expression
    = {- Comes as `{}` in JSON. An empty expression coerces to the hardcoded
         "Audience Size" >> "All Internet Users" question datapoint:

            {
               "question": "q999",
               "datapoints": ["q999_99"],
               "min_count": 1,
               "not": false
            }
      -}
      AllRespondents
    | FirstLevelNode LogicOperator (NonEmpty.NonEmpty ExpressionHelp)
      {- `Audience` `Expression`s actually do not come as `LeafData`, they are always
         wrapped around an operator (`Or` is the most suitable when none is specified).

         Crosstabs app works differently and it allows to have a first level leaf as a
         whole `Expression`. There are lots of instances where this happens, so we need
         to keep this type here... However, bear in mind that whenever we work with the
         _Audience Builder_ app, we need to wrap it around a `FirstLevelNode` with an `Or`
         operator.
      -}
    | FirstLevelLeaf LeafData


expressionToExpressionHelp : Expression -> ExpressionHelp
expressionToExpressionHelp expression =
    case expression of
        AllRespondents ->
            Leaf allInternetUsersLeafData

        FirstLevelNode op subExprs ->
            Node op subExprs

        FirstLevelLeaf leafData ->
            Leaf leafData


{-| `AllRespondents` comes as an empty JSON `{}` which is ugly to handle in Elm. So we
use this function to ease cognitive complexity wherever it is decoded.
-}
allRespondentsDecoder : Decode.Decoder Expression
allRespondentsDecoder =
    let
        fromPairs xs =
            case xs of
                [] ->
                    Decode.succeed AllRespondents

                [ ( _, () ) ] ->
                    Decode.succeed AllRespondents

                _ ->
                    Decode.fail "Size expression expected to be {}"
    in
    Decode.oneOf
        [ Decode.null AllRespondents
        , Decode.keyValuePairs (Decode.succeed ())
            |> Decode.andThen fromPairs
        ]


{-| `Expressions` are complex nested data structures that can grow infinitely, so we
split the decoders with helpers to ease the cognitive load. This is the graph of calls
done between de `Decoder`s:

```plaintext
                           ┌───────┐
             ┌─────────────┤decoder├───────────────────┐
             │             └───┬───┘                   │
             │                 └───┐                   │
   ┌─────────▼───────────┐ ┌───────▼───────┐ ┌─────────▼───────────┐
   │expressionNodeDecoder│ │leafDataDecoder│ │allRespondentsDecoder│
   └─────────┬───────────┘ └───────▲───────┘ └─────────────────────┘
             │                     │
   ┌─────────▼───────────┐         │
┌──►expressionHelpDecoder├─────────┘
│  └─────────┬───────────┘
│            └─┐
│  ┌───────────▼─────────────┐
└──┤expressionHelpNodeDecoder│
   └─────────────────────────┘
```

-}
decoder : Decode.Decoder Expression
decoder =
    Decode.oneOf
        [ Decode.map FirstLevelLeaf leafDataDecoder
        , expressionNodeDecoder
        , allRespondentsDecoder
        ]


expressionNodeDecoder : Decode.Decoder Expression
expressionNodeDecoder =
    Decode.oneOf
        [ Decode.field (logicOperatorToFieldString And)
            (NonEmpty.decodeList expressionHelpDecoder)
            |> Decode.map (FirstLevelNode And)
        , Decode.field (logicOperatorToFieldString Or)
            (NonEmpty.decodeList expressionHelpDecoder)
            |> Decode.map (FirstLevelNode Or)
        ]


encode : Expression -> Encode.Value
encode expression =
    case expression of
        -- TODO: Comes as `{}` we send it as `null`? Check why.
        AllRespondents ->
            Encode.null

        FirstLevelNode logicOperator nested ->
            Encode.object
                [ ( logicOperatorToFieldString logicOperator
                  , NonEmpty.encodeList encodeExpressionHelp nested
                  )
                ]

        FirstLevelLeaf leafData ->
            encodeLeafData leafData


{-| Since `AllRespondents` can't be nested inside an `Expression`, we created this helper
type to avoid that invalid state.
-}
type ExpressionHelp
    = Leaf LeafData
    | Node LogicOperator (NonEmpty.NonEmpty ExpressionHelp)


expressionHelpDecoder : Decode.Decoder ExpressionHelp
expressionHelpDecoder =
    Decode.oneOf
        [ Decode.map Leaf leafDataDecoder
        , Decode.lazy (\() -> expressionHelpNodeDecoder)
        ]


expressionHelpNodeDecoder : Decode.Decoder ExpressionHelp
expressionHelpNodeDecoder =
    Decode.oneOf
        [ Decode.field (logicOperatorToFieldString And)
            (NonEmpty.decodeList (Decode.lazy (\() -> expressionHelpDecoder)))
            |> Decode.map (Node And)
        , Decode.field (logicOperatorToFieldString Or)
            (NonEmpty.decodeList (Decode.lazy (\() -> expressionHelpDecoder)))
            |> Decode.map (Node Or)
        ]


encodeExpressionHelp : ExpressionHelp -> Encode.Value
encodeExpressionHelp expressionHelp =
    case expressionHelp of
        Leaf leafData ->
            encodeLeafData leafData

        Node logicOperator nested ->
            Encode.object
                [ ( logicOperatorToFieldString logicOperator
                  , NonEmpty.encodeList encodeExpressionHelp nested
                  )
                ]


type alias LeafData =
    { -- 'question'
      namespaceAndQuestionCode : Labels.NamespaceAndQuestionCode

    {- n of them in a `LeafData` are equivalent to n `LeafData`s arranged with `OR`
       operators.

          E.g.:
          { "question": "q1", "datapoints": ["q1_1", "q1_2"] }
          ----------------- is the same as -----------------
          { "question": "q1", "datapoints": ["q1_1"] }
                               OR
          { "question": "q1", "datapoints": ["q1_2"] }
    -}
    -- 'datapoints' (or 'options' for legacy)
    , questionAndDatapointCodes : NonEmpty.NonEmpty Labels.QuestionAndDatapointCode

    {- Same as above happens with suffixes.

       E.g.:
       { "question": "q1", "datapoints": ["q1_1", "q1_2"]. "suffixes": [1, 2] }
       ---------------------------- is the same as ----------------------------
       { "question": "q1", "datapoints": ["q1_1"], "suffixes": [1] }
                                   OR
       { "question": "q1", "datapoints": ["q1_1"], "suffixes": [2] }
                                   OR
       { "question": "q1", "datapoints": ["q1_2"], "suffixes": [1] }
                                   OR
       { "question": "q1", "datapoints": ["q1_2"], "suffixes": [2] }
    -}
    -- 'suffixes'
    , suffixCodes : Optional.Optional (NonEmpty.NonEmpty Suffix.Code)

    -- Is the attribute included or excluded from the audience?
    -- 'not'
    , isExcluded : Optional.Optional Bool

    -- How many datapoints must be included/excluded in the expression
    -- 'min_count'
    , minCount : Optional.Optional Int
    }


encodeLeafData : LeafData -> Encode.Value
encodeLeafData leafData =
    [ ( "question", Id.encode leafData.namespaceAndQuestionCode )
    , ( "datapoints", NonEmpty.encodeList Id.encode leafData.questionAndDatapointCodes )
    ]
        |> Optional.addFieldsToKeyValuePairs
            [ ( "min_count", Optional.map Encode.int leafData.minCount )
            , ( "not", Optional.map Encode.bool leafData.isExcluded )
            , ( "suffixes"
              , Optional.map (NonEmpty.encodeList Suffix.encodeCodeAsString)
                    leafData.suffixCodes
              )
            ]
        |> Encode.object


leafDataDecoder : Decode.Decoder LeafData
leafDataDecoder =
    Decode.map5 LeafData
        (Decode.field "question" Id.decode)
        (Decode.oneOf
            [ Decode.field "datapoints" (NonEmpty.decodeList Id.decode)
            , Decode.field "options" (NonEmpty.decodeList Id.decode)
            ]
        )
        (Optional.decodeField "suffixes" (NonEmpty.decodeList Suffix.codeDecoder))
        (Optional.decodeField "not" Decode.bool)
        (Optional.decodeField "min_count" Decode.int)


{-| This acts like an identity element in monoidal composition of audience expressions.
Anyway only in cases where equality isn't considered for built-in `(==)` operator
(which can't be overloaded in Elm) but when the equality is defined in terms
of which data are returned from API when audience is applied on any arbitrary question.

  - question code `q999` means "Audience Size" (hardcoded constrain of a system)
  - option code `q999_99` means "All Internet users"

So in another words size of rest of expressions for all respondents.
This is guaranteed to yield same data when as any expression `e` when intersected witch such.

    e == intersection e sizeExpression

-}
sizeExpression : Expression
sizeExpression =
    AllRespondents


{-| Hardcoded constraint of our system. This is equals to "All data that is avaiblable".
-}
allInternetUsersLeafData : LeafData
allInternetUsersLeafData =
    { namespaceAndQuestionCode = Id.fromString "q999"
    , questionAndDatapointCodes = NonEmpty.singleton (Id.fromString "q999_99")
    , suffixCodes = Optional.Undefined
    , isExcluded = Optional.Undefined
    , minCount = Optional.Undefined
    }


{-| Merges two expressions with `And`. Any expression merged with `AllRespondents` will
return the same expression.
-}
intersection : Expression -> Expression -> Expression
intersection leftExpr rightExpr =
    case ( leftExpr, rightExpr ) of
        -- Having size AND node = Having node
        ( AllRespondents, FirstLevelNode rightOp rightSubExprs ) ->
            FirstLevelNode rightOp rightSubExprs

        -- Having node AND size = Having node
        ( FirstLevelNode leftOp leftSubExprs, AllRespondents ) ->
            FirstLevelNode leftOp leftSubExprs

        -- Having size AND size = Having size
        ( AllRespondents, AllRespondents ) ->
            AllRespondents

        -- Having size AND leaf = Having leaf
        ( AllRespondents, FirstLevelLeaf rightLeaf ) ->
            FirstLevelLeaf rightLeaf

        -- Having leaf AND size = Having leaf
        ( FirstLevelLeaf leftLeaf, AllRespondents ) ->
            FirstLevelLeaf leftLeaf

        -- Having leaf AND leaf = Having node
        ( FirstLevelLeaf leftLeaf, FirstLevelLeaf rightLeaf ) ->
            FirstLevelNode And ( Leaf leftLeaf, [ Leaf rightLeaf ] )

        -- Having node AND node = Having node
        ( FirstLevelNode leftOp leftSubExprs, FirstLevelNode rightOp rightSubExprs ) ->
            FirstLevelNode And
                ( Node leftOp leftSubExprs
                , [ Node rightOp rightSubExprs ]
                )

        -- Having node AND leaf = Having node
        ( FirstLevelNode leftOp leftSubExprs, FirstLevelLeaf rightLeaf ) ->
            FirstLevelNode And ( Node leftOp leftSubExprs, [ Leaf rightLeaf ] )

        -- Having leaf AND node = Having node
        ( FirstLevelLeaf leftLeaf, FirstLevelNode rightOp rightSubExprs ) ->
            FirstLevelNode And ( Leaf leftLeaf, [ Node rightOp rightSubExprs ] )


{-| Merge several expressions with `And`.
-}
intersectionMany : NonEmpty.NonEmpty Expression -> Expression
intersectionMany expressions =
    if NonEmpty.length expressions == 1 then
        NonEmpty.head expressions

    else
        FirstLevelNode And (NonEmpty.map expressionToExpressionHelp expressions)


{-| Merges two expressions with `Or`. Any expression merged with `AllRespondents` will
return `AllRespondents`.
-}
union : Expression -> Expression -> Expression
union leftExpr rightExpr =
    case ( leftExpr, rightExpr ) of
        -- Having size OR node = Having size
        ( AllRespondents, FirstLevelNode _ _ ) ->
            AllRespondents

        -- Having node OR size = Having size
        ( FirstLevelNode _ _, AllRespondents ) ->
            AllRespondents

        -- Having size OR size = Having size
        ( AllRespondents, AllRespondents ) ->
            AllRespondents

        -- Having size OR leaf = Having size
        ( AllRespondents, FirstLevelLeaf _ ) ->
            AllRespondents

        -- Having leaf OR size = Having size
        ( FirstLevelLeaf _, AllRespondents ) ->
            AllRespondents

        -- Having leaf OR leaf = Having node
        ( FirstLevelLeaf leftLeaf, FirstLevelLeaf rightLeaf ) ->
            FirstLevelNode Or ( Leaf leftLeaf, [ Leaf rightLeaf ] )

        -- Having node OR node = Having node
        ( FirstLevelNode leftOp leftSubExprs, FirstLevelNode rightOp rightSubExprs ) ->
            FirstLevelNode Or
                ( Node leftOp leftSubExprs
                , [ Node rightOp rightSubExprs ]
                )

        -- Having node OR leaf = Having node
        ( FirstLevelNode leftOp leftSubExprs, FirstLevelLeaf rightLeaf ) ->
            FirstLevelNode Or ( Node leftOp leftSubExprs, [ Leaf rightLeaf ] )

        -- Having leaf OR node = Having node
        ( FirstLevelLeaf leftLeaf, FirstLevelNode rightOp rightSubExprs ) ->
            FirstLevelNode Or ( Leaf leftLeaf, [ Node rightOp rightSubExprs ] )


{-| Merge several expressions with `Or`.
-}
unionMany : NonEmpty.NonEmpty Expression -> Expression
unionMany expressions =
    if NonEmpty.length expressions == 1 then
        NonEmpty.head expressions

    else
        FirstLevelNode Or (NonEmpty.map expressionToExpressionHelp expressions)


{-| Merge two `Expression`s with an operator.
-}
append : LogicOperator -> Expression -> Expression -> Expression
append op =
    case op of
        Or ->
            union

        And ->
            intersection


{-| Fold an `Expression` from the right. The function passed as an argument works with
`LeafData`.
-}
foldr : (LeafData -> b -> b) -> b -> Expression -> b
foldr f acc expression =
    case expression of
        AllRespondents ->
            acc

        FirstLevelNode _ subnodes ->
            NonEmpty.foldr (\exp listAcc -> foldrHelp f listAcc exp) acc subnodes

        FirstLevelLeaf leaf ->
            f leaf acc


foldrHelp : (LeafData -> b -> b) -> b -> ExpressionHelp -> b
foldrHelp f acc expressionHelp =
    case expressionHelp of
        Leaf leaf ->
            f leaf acc

        Node _ subnodes ->
            NonEmpty.foldr (\exp listAcc -> foldrHelp f listAcc exp) acc subnodes


getQuestionCodes : Expression -> List Labels.NamespaceAndQuestionCode
getQuestionCodes expression =
    foldr
        (\leaf acc -> leaf.namespaceAndQuestionCode :: acc)
        []
        expression


getQuestionAndDatapointCodes : Expression -> List Labels.QuestionAndDatapointCode
getQuestionAndDatapointCodes expression =
    foldr
        (\leaf acc -> NonEmpty.toList leaf.questionAndDatapointCodes ++ acc)
        []
        expression


getNamespaceCodes : Expression -> List Namespace.Code
getNamespaceCodes expr =
    getQuestionCodes expr
        |> List.map Labels.questionCodeToNamespaceCode
