module ReviewConfig exposing (config)

import AllTextareasWithGrammarlyDisabled
import CognitiveComplexity
import ConsistentImports
import Docs.NoMissing
import Docs.ReviewAtDocs
import Docs.ReviewLinksAndSections
import Docs.UpToDateReadmeLinks
import ExhaustiveCaseOfPatterns
import FewerFunctionArguments
import NoConfusingPrefixOperator
import NoDebug.Log
import NoDebug.TodoOrToString
import NoDecodeAtWithSingleField
import NoDeprecated
import NoEmptyHtmlText
import NoExposingEverything
import NoFontAwesomeOrGwiIcons
import NoHugeExpressions
import NoHugeModules
import NoImportingEverything
import NoLeftPizza
import NoMissingSubscriptionsCall
import NoMissingTypeAnnotation
import NoMissingTypeAnnotationInLetIn
import NoMissingTypeExpose
import NoP2WavesInTV2
import NoPrematureLetComputation
import NoRecursiveUpdate
import NoSimpleLetBody
import NoSinglePatternCase
import NoSlowConcat
import NoUnnecessaryTrailingUnderscore
import NoUnoptimizedRecursion
import NoUnqualifiedFunctions
import NoUnused.CustomTypeConstructorArgs
import NoUnused.CustomTypeConstructors
import NoUnused.Dependencies
import NoUnused.Exports
import NoUnused.Modules
import NoUnused.Parameters
import NoUnused.Patterns
import NoUnused.Variables
import NoUselessSubscriptions
import NoWeakCssWithConstantStates
import Review.Rule as Rule exposing (Rule)
import Simplify
import UseMemoizedLazyLambda
import VariablesBetweenCaseOf.AccessInCases


config : List Rule
config =
    [ NoUnused.CustomTypeConstructors.rule []
    , NoUnused.Dependencies.rule
    , NoUnused.Exports.rule
        |> Rule.ignoreErrorsForFiles
            -- Library-like modules the API of which could seem incomplete if exports were removed
            [ "src/crosstab-builder/XB2/src/XB2/Browser/Debug.elm"
            ]
    , NoUnused.Modules.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/crosstab-builder/XB2/src/XB2/Browser/Debug.elm"
            ]
    , NoUnused.Parameters.rule
    , NoUnused.Patterns.rule
    , NoUnused.Variables.rule
    , NoSlowConcat.rule
    , AllTextareasWithGrammarlyDisabled.rule
    , NoDecodeAtWithSingleField.rule
    , ConsistentImports.rule
    , NoWeakCssWithConstantStates.rule
    , NoLeftPizza.rule NoLeftPizza.Redundant
    , NoEmptyHtmlText.rule
    , NoP2WavesInTV2.rule
    , NoExposingEverything.rule
    , NoImportingEverything.rule [ "Test" ]
    , NoFontAwesomeOrGwiIcons.rule
    , NoDebug.Log.rule
    , Simplify.rule Simplify.defaults
    , NoDebug.TodoOrToString.rule
        |> Rule.ignoreErrorsForFiles
            [ "src/crosstab-builder/XB2/tests/XB2/ColumnLabelTest.elm"
            , "src/crosstab-builder/XB2/tests/XB2/DetailTest.elm"
            ]
    , NoDeprecated.rule NoDeprecated.defaults
    , NoMissingTypeExpose.rule
    , Docs.NoMissing.rule
        { document = Docs.NoMissing.onlyExposed
        , from = Docs.NoMissing.exposedModules
        }
    , Docs.ReviewLinksAndSections.rule
    , Docs.UpToDateReadmeLinks.rule
    , NoSimpleLetBody.rule
    , NoUselessSubscriptions.rule
    ]
        |> List.map
            (Rule.ignoreErrorsForDirectories
                [ "src/crosstab-builder/XB2/src/XB2/Data/Zod"
                , "src/crosstab-builder/XB2/src/XB2/Utils"
                ]
            )


unusedButDesiredRules : List Rule
unusedButDesiredRules =
    [ CognitiveComplexity.rule 15
    , Docs.ReviewAtDocs.rule
    , NoConfusingPrefixOperator.rule
    , NoMissingSubscriptionsCall.rule
    , NoMissingTypeAnnotation.rule
    , NoMissingTypeAnnotationInLetIn.rule
    , NoPrematureLetComputation.rule
    , NoRecursiveUpdate.rule
    , NoUnnecessaryTrailingUnderscore.rule
    , NoUnoptimizedRecursion.rule (NoUnoptimizedRecursion.optOutWithComment "IGNORE TCO")
    , NoUnqualifiedFunctions.rule
    , NoUnused.CustomTypeConstructorArgs.rule
    , UseMemoizedLazyLambda.rule
    , VariablesBetweenCaseOf.AccessInCases.forbid
    , NoHugeExpressions.rule NoHugeExpressions.defaults
    , NoHugeModules.rule NoHugeModules.defaults
    , ExhaustiveCaseOfPatterns.rule
    , FewerFunctionArguments.rule FewerFunctionArguments.defaults
    , NoSinglePatternCase.rule NoSinglePatternCase.fixInArgument
    ]
