{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Cardano.Wallet.Jormungandr.ApiSpec
    ( spec
    ) where

import Prelude

import Cardano.Wallet.Jormungandr.Api.Types
    ( AccountState (..)
    , ApiAccountId (..)
    , ApiStakeDistribution (..)
    , ApiT (..)
    , StakeApiResponse (..)
    )
import Cardano.Wallet.Primitive.Types
    ( PoolId (..) )
import Cardano.Wallet.Unsafe
    ( unsafePoolId )
import Control.Monad
    ( forM_, replicateM )
import Data.Aeson
    ( eitherDecode )
import Data.Aeson.QQ
    ( aesonQQ )
import Data.Proxy
    ( Proxy (..) )
import Data.Quantity
    ( Quantity (..) )
import Data.Text
    ( Text )
import Data.Text.Class
    ( FromText (..), TextDecodingError (..), ToText (..) )
import Data.Word
    ( Word64 )
import Test.Aeson.Internal.RoundtripSpecs
    ( roundtripSpecs )
import Test.Hspec
    ( Spec, describe, it, shouldBe )
import Test.QuickCheck
    ( Arbitrary (..), choose )
import Test.Text.Roundtrip
    ( textRoundtrip )

import qualified Codec.Binary.Bech32 as Bech32
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL

spec :: Spec
spec = do
    describe "Jormungandr Api" $ do

        describe "Textual roundtrip tests for API types" $ do

            textRoundtrip $ Proxy @ApiAccountId

        describe "JSON roundtrip tests for API types" $ do

            roundtripSpecs $ Proxy @AccountState

        it "Valid account IDs are properly decoded from text" $ do

            forM_ testAccountIdTexts $ \text ->
                toText <$> fromText @ApiAccountId text
                    `shouldBe` Right text

        it "Invalid account IDs cannot be decoded from text" $ do

            let invalidAccountIdTexts =
                    [ ""
                    , "not-an-account-id"
                    , "skkalz75s4vtw2e9w"
                    ]
            forM_ invalidAccountIdTexts $ \text ->
                toText <$> fromText @ApiAccountId text
                    `shouldBe` Left
                        (TextDecodingError "Invalid Jormungandr account ID.")

        describe "Example account state objects are properly decoded" $ do

            let testBalance = 1000
            let testTransactionCount = 1
            let testPoolRatio1 = 1
            let testPoolRatio2 = 10

            it "With 0 stake pools" $ do

                let testAccountState = Aeson.encode [aesonQQ|
                        { "value": #{testBalance}
                        , "counter": #{testTransactionCount}
                        , "delegation": {"pools": []}
                        }|]
                eitherDecode testAccountState `shouldBe` Right AccountState
                    { currentBalance = Quantity testBalance
                    , totalTransactionCount = Quantity testTransactionCount
                    , stakePools = []
                    }

            it "With 1 stake pool" $ do

                let testAccountState = Aeson.encode [aesonQQ|
                        { "value": #{testBalance}
                        , "counter": #{testTransactionCount}
                        , "delegation":
                            { "pools":
                                [[#{toText testPoolId1}, #{testPoolRatio1}]]
                            }
                        }|]
                eitherDecode testAccountState `shouldBe` Right AccountState
                    { currentBalance = Quantity testBalance
                    , totalTransactionCount = Quantity testTransactionCount
                    , stakePools = [(testPoolId1, Quantity testPoolRatio1)]
                    }

            it "With n stake pools" $ do

                let testAccountState = Aeson.encode [aesonQQ|
                        { "value": #{testBalance}
                        , "counter": #{testTransactionCount}
                        , "delegation":
                            { "pools":
                                [ [#{toText testPoolId1}, #{testPoolRatio1}]
                                , [#{toText testPoolId2}, #{testPoolRatio2}]
                                ]
                            }
                        }|]
                eitherDecode testAccountState `shouldBe` Right AccountState
                    { currentBalance = Quantity testBalance
                    , totalTransactionCount = Quantity testTransactionCount
                    , stakePools =
                        [ (testPoolId1, Quantity testPoolRatio1)
                        , (testPoolId2, Quantity testPoolRatio2)
                        ]
                    }

        it "example stake endpoint response is properly decoded" $ do
            let exampleStake = "{\"epoch\": 252054,\"stake\": {\"dangling\":0,\"\
                    \pools\":[[\"7d749ef424507fb80fed0d2289d535a94f6870add0cf8b3\
                    \74cfe6cae078320ec\",1]],\"unassigned\":100100000000000}}"
            decodeJSON exampleStake `shouldBe`
                Right StakeApiResponse {
                   epoch = ApiT 252054,
                   stake = ApiStakeDistribution {
                       dangling = ApiT (Quantity 0),
                       pools = [((ApiT (PoolId "}t\158\244$P\DEL\184\SI\237\r\"\137\213\&5\169Ohp\173\208\207\139\&7L\254l\174\a\131 \236"))
                                 , (ApiT (Quantity 1)))],
                       unassigned = ApiT (Quantity 100100000000000)
                       }
                    }
            return ()

        it "example empty stake endpoint response is properly decoded" $ do
            let exampleStake = "{\"epoch\": 252054,\"stake\": {\"dangling\":0,\"\
                    \pools\":[],\"unassigned\":100100000000000}}"
            decodeJSON exampleStake `shouldBe`
                Right StakeApiResponse {
                   epoch = ApiT 252054,
                   stake = ApiStakeDistribution {
                       dangling = ApiT (Quantity 0),
                       pools = [],
                       unassigned = ApiT (Quantity 100100000000000)
                       }
                    }
            return ()

        it "invalid stake pool id in endpoint response gives expected error" $ do
            let exampleStake = "{\"epoch\": 252054,\"stake\": {\"dangling\":0,\"\
                    \pools\":[[\"b80fed0d2289d535a94f6870add0cf8b3\
                    \74cfe6cae078320ec\",1]],\"unassigned\":100100000000000}}"
            decodeJSON exampleStake `shouldBe`
                Left "Error in $.stake.pools[0][0]: stake pool id invalid: \
                     \expected 32 bytes but got 25"
            return ()

        it "invalid stake pool id in endpoint response gives expected error" $ do
            let exampleStake = "{\"epoch\": 252054,\"stake\": {\"dangling\":0,\"\
                    \pools\":[[12345,1]],\"unassigned\":100100000000000}}"
            decodeJSON exampleStake `shouldBe`
                Left "Error in $.stake.pools[0][0]: expected Text, encountered Number"
            return ()

        it "invalid stake pair in endpoint response gives expected error" $ do
            let exampleStake = "{\"epoch\": 252054,\"stake\": {\"dangling\":0,\"\
                    \pools\":[[\"7d749ef424507fb80fed0d2289d535a94f6870add0cf8b3\
                    \74cfe6cae078320ec\",1, \"not needed field\"]],\"unassigned\":\
                    \100100000000000}}"
            decodeJSON exampleStake `shouldBe`
                Left "Error in $.stake.pools[0]: cannot unpack array of length 3\
                     \ into a tuple of length 2"
            return ()

        it "invalid numerical field value in endpoint response gives expected error" $ do
            let exampleStake = "{\"epoch\": 252054,\"stake\": {\"dangling\":0,\"\
                    \pools\":[[\"7d749ef424507fb80fed0d2289d535a94f6870add0cf8b3\
                    \74cfe6cae078320ec\",1]],\"unassigned\":[]}}"
            decodeJSON exampleStake `shouldBe`
                Left "Error in $.stake.unassigned: expected Word64, \
                     \encountered Array"
            return ()

        it "invalid non-numerical field value in endpoint response gives expected error" $ do
            let exampleStake = "{\"epoch\": 252054,\"stake\": {\"dangling\":0,\"\
                    \pools\":[[\"7d749ef424507fb80fed0d2289d535a94f6870add0cf8b3\
                    \74cfe6cae078320ec\",1]],\"unassigned\":-10010000}}"
            decodeJSON exampleStake `shouldBe`
                Left "Error in $.stake.unassigned: Word64 is either floating or \
                     \will cause over or underflow: -1.001e7"
            return ()

        it "invalid non-numerical field value in endpoint response gives expected error" $ do
            let exampleStake = "{\"epoch\": 252054,\"stake\": {\"dangling\":0,\"\
                    \pools\":[[\"7d749ef424507fb80fed0d2289d535a94f6870add0cf8b3\
                    \74cfe6cae078320ec\",1]],\"unassigned\":10010000.23}}"
            decodeJSON exampleStake `shouldBe`
                Left "Error in $.stake.unassigned: Word64 is either floating or \
                     \will cause over or underflow: 1.001000023e7"
            return ()
  where
    decodeJSON = eitherDecode :: BL.ByteString -> Either String StakeApiResponse

{-------------------------------------------------------------------------------
                             Arbitrary Instances
-------------------------------------------------------------------------------}

instance Arbitrary ApiAccountId where
    arbitrary = do
        count <- choose (0, 64)
        ApiAccountId . Bech32.dataPartFromBytes . BS.pack
            <$> replicateM count arbitrary
    shrink _ = []

instance Arbitrary AccountState where
    arbitrary = AccountState
        <$> arbitrary
        <*> arbitrary
        <*> arbitrary

instance Arbitrary PoolId where
    arbitrary = PoolId . BS.pack
        <$> replicateM 32 arbitrary

instance Arbitrary (Quantity "lovelace" Word64) where
    arbitrary = Quantity <$> arbitrary
    shrink (Quantity q) = Quantity <$> shrink q

instance Arbitrary (Quantity "stake-pool-ratio" Word64) where
    arbitrary = Quantity <$> arbitrary
    shrink (Quantity q) = Quantity <$> shrink q

instance Arbitrary (Quantity "transaction-count" Word64) where
    arbitrary = Quantity <$> arbitrary
    shrink (Quantity q) = Quantity <$> shrink q

{-------------------------------------------------------------------------------
                                  Test data
-------------------------------------------------------------------------------}

testAccountIdTexts :: [Text]
testAccountIdTexts =
    [ testAccountIdText1
    , testAccountIdText2
    , testAccountIdText3
    ]

testAccountIdText1 :: Text
testAccountIdText1 =
    "ca1skkalz75s4vtw2e9wsy2q9jvsu3qtz6d2vm3xj4e5q4ufejpjjfn5lh35yr"

testAccountIdText2 :: Text
testAccountIdText2 =
    "ca1shqtmpgefmhlwrwlm48kxq43hpkxnvz8fey2jlmce5lea3mxnskfqr99fz4"

testAccountIdText3 :: Text
testAccountIdText3 =
    "ca1skzn99jx8a2rw80gp9uea47tmcndv7gm28vy9as6akevy32204aqwzpsctx"

testPoolId1 :: PoolId
testPoolId1 = unsafePoolId
    "c780f14f9782770014d8bcd514b1bc664653d15f73a7158254730c6e1aa9f356"

testPoolId2 :: PoolId
testPoolId2 = unsafePoolId
    "653f9aa1e6c0374528517a37f51d356466cb1b415dcb8d4100772879f41f087c"
