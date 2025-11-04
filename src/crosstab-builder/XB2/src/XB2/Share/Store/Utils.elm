module XB2.Share.Store.Utils exposing
    ( Resource
    , collectionToAnyDict
    , destroy
    , fetch
    , filterResource
    , get
    , getByIds
    , getByIdsIfAllDone
    , getByIdsIfAllLoaded
    , getFromAnyDict
    , insertResource
    , modify
    , peek
    , removeResource
    , taggedCollectionLoaded
    , taggedCollectionLoadedWith
    )

-- Modules

import Basics.Extra exposing (flip)
import Dict.Any
import Http
import Maybe.Extra as Maybe
import RemoteData exposing (RemoteData(..), WebData)
import Result.Extra as Result
import XB2.Share.Config exposing (Flags)
import XB2.Share.Data.Id exposing (Id, IdDict)
import XB2.Share.Gwi.Http exposing (Error, HttpCmd)


get : WebData (IdDict tag a) -> Id tag -> Maybe a
get state id =
    Maybe.andThen (Dict.Any.get id) <| RemoteData.toMaybe state


getFromAnyDict : WebData (Dict.Any.AnyDict comparable k v) -> k -> Maybe v
getFromAnyDict state key =
    Maybe.andThen (Dict.Any.get key) <| RemoteData.toMaybe state


getByIds : WebData (IdDict tag a) -> List (Id tag) -> List a
getByIds state ids =
    case state of
        -- Faster than `List.filterMap (get state) ids` because we avoid repeated unwrapping of RemoteData
        Success dict ->
            List.filterMap (\id -> Dict.Any.get id dict) ids

        _ ->
            []


getByIdsIfAllLoaded : IdDict tag (WebData a) -> List (Id tag) -> Maybe (IdDict tag a)
getByIdsIfAllLoaded dict ids =
    ids
        |> Maybe.traverse
            (\id ->
                Dict.Any.get id dict
                    |> Maybe.andThen RemoteData.toMaybe
                    |> Maybe.map (Tuple.pair id)
            )
        |> Maybe.map XB2.Share.Data.Id.dictFromList


getByIdsIfAllDone : IdDict tag (WebData a) -> List (Id tag) -> Maybe (IdDict tag a)
getByIdsIfAllDone dict ids =
    ids
        |> List.foldr
            (\id acc ->
                case ( Dict.Any.get id dict, acc ) of
                    ( Just (Success item), Just acc_ ) ->
                        Just <| ( id, item ) :: acc_

                    ( Just (Failure _), Just _ ) ->
                        acc

                    _ ->
                        Nothing
            )
            (Just [])
        |> Maybe.map XB2.Share.Data.Id.dictFromList



-- Network


collectionRequest :
    (err -> Http.Error)
    -> (b -> msg)
    -> ((store -> store) -> Error err -> msg)
    -> (Flags -> HttpCmd err b)
    -> (store -> Maybe Http.Error -> store)
    -> Flags
    -> store
    -> ( store, Cmd msg )
collectionRequest customErrorToHttpError success fail requestCmd setState flags store =
    let
        httpResultToMsg =
            Result.unpack
                (\e -> fail (flip setState <| Just <| XB2.Share.Gwi.Http.toHttpError customErrorToHttpError e) e)
                success
    in
    ( setState store Nothing
    , Cmd.map httpResultToMsg <| requestCmd flags
    )


fetch :
    (err -> Http.Error)
    -> (store -> WebData a)
    -> (b -> msg)
    -> ((store -> store) -> Error err -> msg)
    -> (Flags -> HttpCmd err b)
    -> (store -> Maybe Http.Error -> store)
    -> Flags
    -> store
    -> ( store, Cmd msg )
fetch customErrorToHttpError getState success fail requestCmd setState flags store =
    case getState store of
        Loading ->
            ( store, Cmd.none )

        _ ->
            collectionRequest customErrorToHttpError
                success
                fail
                requestCmd
                setState
                flags
                store


peek :
    (err -> Http.Error)
    -> (store -> WebData a)
    -> (b -> msg)
    -> ((store -> store) -> Error err -> msg)
    -> (Flags -> HttpCmd err b)
    -> (store -> Maybe Http.Error -> store)
    -> Flags
    -> store
    -> ( store, Cmd msg )
peek customErrorToHttpError getState success fail requestCmd setState flags store =
    case getState store of
        NotAsked ->
            fetch customErrorToHttpError getState success fail requestCmd setState flags store

        _ ->
            ( store, Cmd.none )


resourceReq :
    (res -> a)
    -> (store -> WebData (IdDict tag a))
    -> (a -> msg)
    -> (Error err -> msg)
    -> (a -> Flags -> HttpCmd err res)
    -> a
    -> (store -> store)
    -> Flags
    -> store
    -> ( store, Cmd msg )
resourceReq toRes getState success fail requestCmd model updateS flags store =
    ( updateS store
    , case getState store of
        Success _ ->
            let
                httpResultToMsg =
                    Result.unpack fail (success << toRes)
            in
            Cmd.map httpResultToMsg <| requestCmd model flags

        _ ->
            Cmd.none
    )


modify :
    (store -> WebData (IdDict tag a))
    -> (a -> msg)
    -> (Error err -> msg)
    -> (a -> Flags -> HttpCmd err a)
    -> a
    -> (store -> store)
    -> Flags
    -> store
    -> ( store, Cmd msg )
modify =
    resourceReq identity


destroy :
    (store -> WebData (IdDict tag a))
    -> (a -> msg)
    -> (Error err -> msg)
    -> (a -> Flags -> HttpCmd err ())
    -> a
    -> (store -> store)
    -> Flags
    -> store
    -> ( store, Cmd msg )
destroy getState success fail requestCmd model =
    resourceReq (always model) getState success fail requestCmd model



-- Store updates


type alias Resource a tag =
    { a | id : Id tag }


taggedCollectionLoaded : List (Resource a tag) -> WebData (IdDict tag (Resource a tag))
taggedCollectionLoaded =
    taggedCollectionLoadedWith .id


collectionToAnyDict :
    List a
    -> (a -> b)
    -> (b -> comparable)
    -> Dict.Any.AnyDict comparable b a
collectionToAnyDict list idFieldAccessor idToComparable =
    Dict.Any.fromList idToComparable (List.map (\el -> ( idFieldAccessor el, el )) list)


taggedCollectionLoadedWith : (a -> Id tag) -> List a -> RemoteData e (IdDict tag a)
taggedCollectionLoadedWith toKey =
    Success << XB2.Share.Data.Id.dictFromList << List.map (\c -> ( toKey c, c ))


insertResource : WebData (IdDict tag (Resource a tag)) -> Resource a tag -> WebData (IdDict tag (Resource a tag))
insertResource state model =
    RemoteData.map (Dict.Any.insert model.id model) state


removeResource : WebData (IdDict tag a) -> Id tag -> WebData (IdDict tag a)
removeResource state id =
    RemoteData.map (Dict.Any.remove id) state


filterResource : (Id tag -> a -> Bool) -> WebData (IdDict tag a) -> WebData (IdDict tag a)
filterResource reducer =
    RemoteData.map (Dict.Any.filter reducer)
