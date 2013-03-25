{-# LANGUAGE Rank2Types #-}
module Control.Monad.ST.Logic
       ( LogicST
       , runLogicST
       , observeST
       , observeAllST
       , observeManyST
       , liftST
       , STRef
       , newSTRef
       , readSTRef
       , writeSTRef
       , modifySTRef
       , modifySTRef'
       ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Logic
import Control.Monad.ST.Safe

import qualified Data.STRef as ST

newtype LogicST s a =
  LogicST { unLogicST :: Flag s -> LogicT (ST s) a
          }

runLogicST :: LogicST s a -> (a -> ST s r -> ST s r) -> ST s r -> ST s r
runLogicST m plus zero = do
  flag <- newFlag
  runLogicT (unLogicST m flag) plus zero

observeST :: LogicST s a -> ST s a
observeST m = newFlag >>= observeT . unLogicST m

observeAllST :: LogicST s a -> ST s [a]
observeAllST m = newFlag >>= observeAllT . unLogicST m

observeManyST :: Int -> LogicST s a -> ST s [a]
observeManyST n m = newFlag >>= observeManyT n . unLogicST m

liftST :: ST s a -> LogicST s a
liftST = liftReaderT . lift

mapReaderT :: (LogicT (ST s) a -> LogicT (ST s) b) -> LogicST s a -> LogicST s b
mapReaderT f m = LogicST $ f . unLogicST m

liftReaderT :: LogicT (ST s) a -> LogicST s a
liftReaderT = LogicST . const

instance Functor (LogicST s) where
  fmap = mapReaderT . fmap

instance Applicative (LogicST s) where
  pure = liftReaderT . pure
  f <*> a = LogicST $ \ r -> unLogicST f r <*> unLogicST a r

instance Alternative (LogicST s) where
  empty = liftReaderT empty
  m <|> n = LogicST $ \ r ->
    lift newFlag >>= \ r' ->
    unLogicST m r' <|>
    (markFlag r' >> unLogicST n r)

instance Monad (LogicST s) where
  return = liftReaderT . return
  m >>= k = LogicST $ \ r -> do
    a <- unLogicST m r
    unLogicST (k a) r
  fail = liftReaderT . fail

instance MonadPlus (LogicST s) where
  mzero = liftReaderT mzero
  m `mplus` n =
    LogicST $ \ r ->
    lift newFlag >>= \ r' ->
    unLogicST m r' `mplus`
    (markFlag r' >> unLogicST n r)

instance MonadLogic (LogicST s) where
  msplit m = LogicST $ fmap (fmap (fmap liftReaderT)) . msplit . unLogicST m

ask :: LogicST s (Flag s)
ask = LogicST return

type Flag s = ST.STRef s Bool

newFlag :: ST s (Flag s)
newFlag = ST.newSTRef False

markFlag :: Flag s -> LogicT (ST s) ()
markFlag = lift . flip ST.writeSTRef True

ifMarked :: Flag s -> ST s a -> ST s a -> ST s a
ifMarked flag t f = do
  p <- ST.readSTRef flag
  if p then t else f

newtype STRef s a = STRef (ST.STRef s (Value s a))

data Value s a
  = New {-# UNPACK #-} !(Write s a)
  | {-# UNPACK #-} !(Write s a) :| !(Value s a)

data Write s a = Write {-# UNPACK #-} !(Flag s) a

newSTRef :: a -> LogicST s (STRef s a)
newSTRef a = ask >>= liftST . fmap STRef . ST.newSTRef .! New . flip Write a

infixr 9 .!
(.!) :: (b -> c) -> (a -> b) -> a -> c
f .! g = \ a -> a `seq` f (g a)

readSTRef :: STRef s a -> LogicST s a
readSTRef (STRef ref) = liftST $ backtrack =<< ST.readSTRef ref
  where
    backtrack (Write flag a :| xs) = ifMarked flag (go xs) (return a)
    backtrack (New (Write _ a)) = return a
    go xs@(Write flag a :| ys) =
      ifMarked flag (go ys) (ST.writeSTRef ref xs >> return a)
    go xs@(New (Write _ a)) = ST.writeSTRef ref xs >> return a

writeSTRef :: STRef s a -> a -> LogicST s ()
writeSTRef ref a = modifySTRef'' ref $ \ (Write flag _) -> Write flag a

modifySTRef :: STRef s a -> (a -> a) -> LogicST s ()
modifySTRef ref f = modifySTRef'' ref $ \ (Write flag a) -> Write flag (f a)

modifySTRef' :: STRef s a -> (a -> a) -> LogicST s ()
modifySTRef' ref f = modifySTRef'' ref $ \ (Write flag a) -> Write flag $! f a

modifySTRef'' :: STRef s a -> (Write s a -> Write s a) -> LogicST s ()
modifySTRef'' (STRef ref) f =
  LogicST $ \ r -> lift $ ST.readSTRef ref >>= backtrack r
  where
    backtrack r xs@(x@(Write flag _) :| ys) =
      ifMarked flag
      (backtrack r ys)
      (ST.writeSTRef ref $! (f x) :| if flag == r then ys else xs)
    backtrack r xs@(New x@(Write flag _)) =
      ST.writeSTRef ref $!
      if flag == r then New (f x) else (f x) :| xs
