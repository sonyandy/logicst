{-# LANGUAGE Rank2Types #-}
module Control.Monad.IO.Logic
       ( LogicIO
       , runLogicIO
       , observeIO
       , observeAllIO
       , observeManyIO
       ) where

import Control.Monad.ST.Logic.Internal

type LogicIO s = LogicT s IO

runLogicIO :: (forall s . LogicIO s a) -> (a -> IO r -> IO r) -> IO r -> IO r
runLogicIO = runLogicT
{-# INLINE runLogicIO #-}

observeIO :: (forall s . LogicIO s a) -> IO a
observeIO = observeT
{-# INLINE observeIO #-}

observeAllIO :: (forall s . LogicIO s a) -> IO [a]
observeAllIO = observeAllT
{-# INLINE observeAllIO #-}

observeManyIO :: Int -> (forall s . LogicIO s a) -> IO [a]
observeManyIO = observeManyT
{-# INLINE observeManyIO #-}
