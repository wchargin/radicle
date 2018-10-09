module Radicle.Internal.AuthenticatedData
  ( mkPr
    oof
  , checkProof
  , toHashData
  ) where

import           Protolude hiding (hash)

import qualified Data.Map.Strict as Map

import           Radicle.Internal.Core
import           Radicle.Internal.Hash
import qualified Radicle.Internal.Merkle as Merkle

type BS = ByteString

data Loc = NthOfVec Int Int | HasKeyVal Int BS deriving (Show)

data Claim = Claim [Loc] BS deriving (Show)

data RadProofElem
  = PfNthOfVec Merkle.Proof
  | PfHasKey Int Merkle.Proof
  deriving (Show)

type RadProof = [RadProofElem]

data HashData
  =
  -- | A simple value
    HashValue BS
  -- | A vector of nested values
  | HashVec (Merkle.MerkleTree HashData)
  -- | A dict of nested values, represented as key-value pairs, with hashed key.
  | HashDict (Merkle.MerkleTree (BS, HashData))
  deriving (Show)

instance Merkle.HasHash HashData where
  hashed = \case
    HashValue h -> hashElem h
    HashVec t -> hashVec (Merkle.hashed t)
    HashDict t -> hashDict (Merkle.hashed t)

hashElem, hashVec, hashDict :: BS -> BS
hashElem x = Merkle.combi ["elem", x]
hashVec x = Merkle.combi ["vector", x]
hashDict x = Merkle.combi ["dict", x]

hashKeyValue :: BS -> BS -> BS
hashKeyValue k v = Merkle.combi ["key-value", k, v]

instance Merkle.HasHash (BS, HashData) where
  hashed (k, v) = hashKeyValue k (Merkle.hashed v)

mkProof :: HashData -> Claim -> Maybe RadProof
mkProof (HashValue h) (Claim [] h') =
  if h == h' then Just [] else Nothing
mkProof (HashVec t) (Claim (NthOfVec _ i : locs) h) = do
  (x, pf) <- Merkle.mkProof i t
  rest <- mkProof x (Claim locs h)
  pure (PfNthOfVec pf : rest)
mkProof (HashDict t) (Claim (HasKeyVal _ k : locs) h) = do
    i <- Merkle.getIndex isKey t
    ((_, x), pf) <- Merkle.mkProof i t
    rest <- mkProof x (Claim locs h)
    pure (PfHasKey i pf : rest)
  where
    isKey (k', _) = k == k'
mkProof _ _ = Nothing

zipProof :: Claim -> RadProof -> BS -> Maybe BS
zipProof (Claim [] h) [] el
  | hashElem h == hashElem el = pure $ hashElem el
  | otherwise = Nothing
zipProof (Claim (loc:locs) h) (x:pf) el = case (loc, x) of
  (NthOfVec n i, PfNthOfVec p) -> do
    h' <- zipProof (Claim locs h) pf el
    h'' <- Merkle.zipProof (Merkle.At n i h') p
    pure . hashVec $ h''
  (HasKeyVal n k, PfHasKey i p) -> do
    h' <- zipProof (Claim locs h) pf el
    h'' <- Merkle.zipProof (Merkle.At n i (hashKeyValue k h')) p
    pure . hashDict $ h''
  _ -> Nothing
zipProof _ _ _ = Nothing

checkProof :: Claim -> RadProof -> BS -> BS -> Bool
checkProof claim pf el rootHash =
  zipProof claim pf el == Just rootHash

toHashData :: Value -> Maybe HashData
toHashData = \case
    Vec xs -> do
      ys <- traverse toHashData (toList xs)
      let t = Merkle.mkMerkleTree ys
      pure $ HashVec t
    Dict m -> do
      let kvs = Map.toList m
      ys <- traverse toHashData (snd <$> kvs)
      let ks = hashRad . fst <$> kvs
      let t = Merkle.mkMerkleTree (zip ks ys)
      pure $ HashDict t
    v -> Just . HashValue $ hashRad v

-- foo = do
--     xs <- val "[:a 1 {:foo 42 :bar 2}]"
--     a <- val ":a"
--     kFoo <- val ":foo"
--     fourtyTwo <- val "42"
--     hd <- toHashData xs
--     let rootHash = Merkle.hashed hd
--     let claim = Claim [NthOfVec 3 2, HasKeyVal 2 (hashRad kFoo)] (hashRad fourtyTwo)
--     pf <- mkProof hd claim
--     z <- zipProof claim pf (hashRad fourtyTwo)
--     --pure (z, rootHash)
--     --pure (z == rootHash)
--     pure (checkProof claim pf (hashRad fourtyTwo) rootHash)
--   where
--     val :: Text -> Maybe Value
--     val t = either (const Nothing) Just (parse "" t)