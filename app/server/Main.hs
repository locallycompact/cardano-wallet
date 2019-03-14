{-# LANGUAGE QuasiQuotes #-}

{-
   This module parses command line arguments and starts the wallet.

   This should be the only module that has a notion of command line arguments.
   Although, for development purposes, we may extend the docopt specification
   here and call `getArgs` where it is needed.
-}
module Main where

import Prelude

import Cardano.NetworkLayer
    ( listen )
import Cardano.Wallet.Primitive
    ( Block )
import Control.Monad
    ( when )
import Fmt
    ( build, fmt )
import System.Console.Docopt
    ( Arguments
    , Docopt
    , Option
    , docopt
    , exitWithUsage
    , getArgOrExitWith
    , isPresent
    , longOption
    , parseArgsOrExit
    )
import System.Environment
    ( getArgs )
import Text.Read
    ( readMaybe )

import qualified Cardano.NetworkLayer.HttpBridge as HttpBridge
import qualified Data.Text as T
import qualified Data.Text.IO as T

-- | Command-Line Interface specification. See http://docopt.org/
cli :: Docopt
cli = [docopt|
cardano-wallet-server

Start the cardano wallet along with its API and underlying node.

Usage:
  cardano-wallet-server [options]
  cardano-wallet-server --help

Options:
  --wallet-server-port <PORT>  port used for serving the wallet API [default: 8090]
  --node-port <PORT>           port used for node-wallet communication [default: 8080]
  --network <NETWORK>          mainnet or testnet [default: mainnet]
|]


data Network = Mainnet | Testnet
    deriving (Show, Enum)

main :: IO ()
main = do
    args <- parseArgsOrExit cli =<< getArgs
    when (args `isPresent` (longOption "help")) $ exitWithUsage cli

    networkName <- getArg args (longOption "network") readNetwork
    nodePort <- getArg args (longOption "node-port") readInt
    _ <- getArg args (longOption "wallet-server-port") readInt

    network <- HttpBridge.newNetworkLayer (showNetwork networkName) nodePort
    listen network logBlock
  where
    logBlock :: Block -> IO ()
    logBlock = T.putStrLn . fmt . build

-- Functions for parsing the values of command line options
--
-- As the Left cases will just be used for printing in this module, we use
-- @String@ for now.

readInt :: String -> Either String Int
readInt str =
    maybe (Left err) Right (readMaybe str)
  where
    err = "Not an integer: " ++ show str ++ "."

readNetwork :: String -> Either String Network
readNetwork "mainnet" = Right Mainnet
readNetwork "testnet" = Right Testnet
readNetwork s = Left $ show s ++ " is neither \"mainnet\" nor \"testnet\"."

showNetwork :: Network -> T.Text
showNetwork = T.toLower . T.pack . show

getArg
    :: Arguments
    -> Option
    -> (String -> Either String a)
    -> IO a
getArg args opt decode = do
    str <- getArgOrExitWith cli args opt
    case decode str of
        Right a -> return a
        Left err -> do
            putStrLn $ "Invalid " <> show opt <> ". " <> err
            putStrLn ""
            exitWithUsage cli
