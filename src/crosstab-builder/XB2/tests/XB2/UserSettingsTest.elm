module XB2.UserSettingsTest exposing (suite)

import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import XB2.Data exposing (DoNotShowAgain(..))


doNotShowDeleteRowsColumnsModal : String
doNotShowDeleteRowsColumnsModal =
    """
    {
        "data":
        {
            "can_show_shared_project_warning": true,
            "xb2_list_ftue_seen": false,
            "do_not_show_again": [
                "DeleteRowsColumnsModal"
            ]
        }
}"""


doNotShowDeleteBasesModal : String
doNotShowDeleteBasesModal =
    """
    {
        "data":
        {
            "can_show_shared_project_warning": true,
            "xb2_list_ftue_seen": true,
            "do_not_show_again": [
                "DeleteBasesModal"
            ]
        }
}"""


doNotShowAll : String
doNotShowAll =
    """
    {
        "data":
        {
            "can_show_shared_project_warning": false,
            "xb2_list_ftue_seen": true,
            "do_not_show_again": [
                "DeleteRowsColumnsModal",
                "DeleteBasesModal"
            ]
        }
}"""


nonExistentSetting : String
nonExistentSetting =
    """
    {
        "data":
        {
            "can_show_shared_project_warning": false,
            "xb2_list_ftue_seen": false,
            "do_not_show_again": [
                "UserSettingThatWillNeverExist"
            ]
        }
}"""


showComplexExpressionOnboarding : String
showComplexExpressionOnboarding =
    """
    {
        "data":
        {
            "can_show_shared_project_warning": false,
            "xb2_list_ftue_seen": false,
            "do_not_show_again": [
                "UserSettingThatWillNeverExist"
            ],
            "show_complex_expressions_onboarding": "step_3_of_6"
        }
}"""


suite : Test
suite =
    describe "XB2.UserSettings"
        [ describe "xbUserSettingsDecoder"
            [ test "doNotShowDeleteRowsColumnsModal" <|
                \() ->
                    Decode.decodeString XB2.Data.xbUserSettingsDecoder doNotShowDeleteRowsColumnsModal
                        |> Result.toMaybe
                        |> Expect.equal
                            (Just
                                { canShowSharedProjectWarning = True
                                , xb2ListFTUESeen = False
                                , doNotShowAgain = [ DeleteRowsColumnsModal ]
                                , showDetailTableInDebugMode = False
                                , pinDebugOptions = False
                                }
                            )
            , test "doNotShowDeleteBasesModal" <|
                \() ->
                    Decode.decodeString XB2.Data.xbUserSettingsDecoder doNotShowDeleteBasesModal
                        |> Result.toMaybe
                        |> Expect.equal
                            (Just
                                { canShowSharedProjectWarning = True
                                , xb2ListFTUESeen = True
                                , doNotShowAgain = [ DeleteBasesModal ]
                                , showDetailTableInDebugMode = False
                                , pinDebugOptions = False
                                }
                            )
            , test "doNotShowAll" <|
                \() ->
                    Decode.decodeString XB2.Data.xbUserSettingsDecoder doNotShowAll
                        |> Result.toMaybe
                        |> Expect.equal
                            (Just
                                { canShowSharedProjectWarning = False
                                , xb2ListFTUESeen = True
                                , doNotShowAgain = [ DeleteRowsColumnsModal, DeleteBasesModal ]
                                , showDetailTableInDebugMode = False
                                , pinDebugOptions = False
                                }
                            )
            , test "doNotBreakOnNonExistentUserSetting" <|
                \() ->
                    Decode.decodeString XB2.Data.xbUserSettingsDecoder nonExistentSetting
                        |> Result.toMaybe
                        |> Expect.equal
                            (Just
                                { canShowSharedProjectWarning = False
                                , xb2ListFTUESeen = False
                                , doNotShowAgain = []
                                , showDetailTableInDebugMode = False
                                , pinDebugOptions = False
                                }
                            )
            , test "show Complex Expression Onboarding" <|
                \() ->
                    Decode.decodeString XB2.Data.xbUserSettingsDecoder showComplexExpressionOnboarding
                        |> Result.toMaybe
                        |> Expect.equal
                            (Just
                                { canShowSharedProjectWarning = False
                                , xb2ListFTUESeen = False
                                , doNotShowAgain = []
                                , showDetailTableInDebugMode = False
                                , pinDebugOptions = False
                                }
                            )
            ]
        ]
