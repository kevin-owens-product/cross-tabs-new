module XB2.Share.Factory.Question exposing (mock)

import List.NonEmpty as NonEmpty
import XB2.Data.Namespace as Namespace
import XB2.Share.Data.Id as Id
import XB2.Share.Data.Labels as Labels


mock : Labels.Question
mock =
    { code = Id.fromString ""
    , longCode = Id.fromString ""
    , namespaceCode = Namespace.coreCode
    , name = ""
    , fullName = ""
    , categoryIds = []
    , suffixes = Nothing
    , message = Nothing
    , accessible = True
    , notice = Nothing
    , averagesUnit = Nothing
    , averageSupport = False
    , warning = Nothing
    , knowledgeBase = Nothing
    , datapoints =
        NonEmpty.singleton
            { code = Id.fromString ""
            , name = ""
            , accessible = True
            , midpoint = Nothing
            , order = 1
            }
    }
