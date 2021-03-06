{-# Language OverloadedStrings #-}
{-|
Module      : Client.View.UserList
Description : Line renderers for channel user list view
Copyright   : (c) Eric Mertens, 2016
License     : ISC
Maintainer  : emertens@gmail.com

This module renders the lines used in the channel user list.
-}
module Client.View.UserList
  ( userListImages
  , userInfoImages
  ) where

import           Client.Image.Message
import           Client.Image.PackedImage
import           Client.Image.Palette
import           Client.State
import           Client.State.Channel
import           Client.State.Network
import           Control.Lens
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Map.Strict as Map
import           Data.List
import           Data.Maybe
import           Data.Ord
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LText
import           Graphics.Vty.Attributes
import           Irc.Identifier
import           Irc.UserInfo

-- | Render the lines used by the @/users@ command in normal mode.
-- These lines show the count of users having each channel mode
-- in addition to the nicknames of the users.
userListImages ::
  Text        {- ^ network -} ->
  Identifier  {- ^ channel -} ->
  ClientState                 ->
  [Image']
userListImages network channel st =
  case preview (clientConnection network) st of
    Just cs -> userListImages' cs channel st
    Nothing -> [text' (view palError pal) "No connection"]
  where
    pal = clientPalette st

userListImages' :: NetworkState -> Identifier -> ClientState -> [Image']
userListImages' cs channel st =
    [countImage, mconcat (intersperse gap (map renderUser usersList))]
  where
    countImage = drawSigilCount pal (map snd usersList)

    matcher = fromMaybe (const True) (clientMatcher st)

    myNicks = clientHighlights cs st

    renderUser (ident, sigils) =
      string (view palSigil pal) sigils <>
      coloredIdentifier pal NormalIdentifier myNicks ident

    gap = char defAttr ' '

    matcher' (ident,sigils) = matcher (LText.fromChunks [Text.pack sigils, idText ident])

    usersList = sortBy (comparing fst)
              $ filter matcher'
              $ HashMap.toList usersHashMap

    pal = clientPalette st

    usersHashMap =
      view (csChannels . ix channel . chanUsers) cs

drawSigilCount :: Palette -> [String] -> Image'
drawSigilCount pal sigils =
  text' (view palLabel pal) "Users:" <> mconcat entries
  where
    sigilCounts = Map.fromListWith (+) [ (take 1 sigil, 1::Int) | sigil <- sigils ]

    entries
      | Map.null sigilCounts = [" 0"]
      | otherwise = [ string (view palSigil pal) (' ':sigil) <>
                      string defAttr (show n)
                    | (sigil,n) <- Map.toList sigilCounts
                    ]


-- | Render lines for the @/users@ command in detailed view.
-- Each user will be rendered on a separate line with username
-- and host visible when known.
userInfoImages ::
  Text        {- ^ network -} ->
  Identifier  {- ^ channel -} ->
  ClientState                 ->
  [Image']
userInfoImages network channel st =
  case preview (clientConnection network) st of
    Just cs -> userInfoImages' cs channel st
    Nothing -> [text' (view palError pal) "No connection"]
  where
    pal = clientPalette st

userInfoImages' :: NetworkState -> Identifier -> ClientState -> [Image']
userInfoImages' cs channel st = countImage : map renderEntry usersList
  where
    matcher = fromMaybe (const True) (clientMatcher st)

    countImage = drawSigilCount pal (map snd usersList)

    myNicks = clientHighlights cs st

    pal = clientPalette st

    renderEntry ((info, acct), sigils) =
      string (view palSigil pal) sigils <>
      coloredUserInfo pal DetailedRender myNicks info <>
      " " <> text' (view palMeta pal) (cleanText acct)

    matcher' ((info, acct),sigils) =
      matcher (LText.fromChunks [Text.pack sigils, renderUserInfo info, " ", acct])

    userInfos = view csUsers cs

    toInfo nick =
      case view (at nick) userInfos of
        Just (UserAndHost n h a) -> (UserInfo nick n h, a)
        Nothing                  -> (UserInfo nick "" "", "")

    usersList = sortBy (flip (comparing (userNick . fst . fst)))
              $ filter matcher'
              $ map (over _1 toInfo)
              $ HashMap.toList usersHashMap

    usersHashMap = view (csChannels . ix channel . chanUsers) cs
