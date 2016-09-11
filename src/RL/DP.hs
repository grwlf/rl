{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TemplateHaskell #-}
module RL.DP where

import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Set as Set
import Prelude hiding(break)

import RL.Imports
import RL.Types as RL

-- type Probab = Rational

-- | Policy
type P s a = HashMap s (Set (a,Probability))


-- FIXME: Convert to fold-like style eventially
-- | Dynamic Programming Problem. Parameters have the following meaning: @num@ -
-- Type of Numbers; @pr@ - the problem; @s@ - State; @a@ - Action
class (Monad m, Ord s, Ord a, Fractional num, Ord num, Hashable s) =>
    DP_Problem pr m s a num | pr -> m, pr -> s, pr -> a, pr -> num where
  dp_states :: pr -> Set s
  dp_actions :: pr -> s -> Set a
  dp_transitions :: pr -> s -> a -> Set (s, Probability)
  dp_reward :: pr -> s -> a -> s -> num
  -- FIXME: think about splitting terminal and non-terminal states
  dp_terminal_states :: pr -> Set s
  dp_action :: pr -> P s a -> s -> Set (a,Probability)

  dp_trace :: pr -> StateVal num s -> P s a -> m ()

-- | Dynamic Programming Policy. Parameters have same meaning as in DP_Problem,
-- @p@ means the Policy
-- class (DP_Problem pr m s a num) => DP_Policy pr m p s a num where

zero_sate_values :: (DP_Problem pr m s a num)
  => pr -> StateVal num s
zero_sate_values pr =  StateVal $ Map.fromList $ map (\s -> (s,0.0)) (Set.toList $ dp_states pr)

-- | For given state, probabilities for all possible action should sum up to 1
invariant_probable_actions :: (DP_Problem pr m s a num, Show s, Show a) => pr -> Bool
invariant_probable_actions pr =
  flip all (dp_states pr) $ \s ->
    flip all (dp_actions pr s) $ \a ->
      case sum (map snd (Set.toList (dp_transitions pr s a))) of
        1 -> True
        x -> error $ "Total probability of state " ++ show s ++ " action " ++ show a ++ " sum up to " ++ show x

-- | No action leads to unlisted state
invariant_closed_transition :: (DP_Problem pr m s a num, Show s, Show a) => pr -> Bool
invariant_closed_transition pr =
  flip all (dp_states pr) $ \s ->
    flip all (dp_actions pr s) $ \a ->
      flip all (dp_transitions pr s a) $ \(s',p) ->
        case (Set.member s' (dp_states pr)) of
          True -> True
          False -> error $ "State " ++ show s ++ ", action " ++ show a ++ " lead to invalid state " ++ show s'

-- | Terminal states are dead ends and non-terminal states are not
invariant_no_dead_states :: (DP_Problem pr m s a num, Show s, Show a) => pr -> Bool
invariant_no_dead_states pr =
  flip all (dp_states pr) $ \s ->
    case (member s (dp_terminal_states pr), Set.null (dp_actions pr s)) of
      (True,True) -> True
      (True,False) -> error $ "Terminal state " ++ show s ++ " is not dead end"
      (False,False) -> True
      (False,True) -> error $ "State " ++ show s ++ " is dead end"

-- Terminals are valid states
invariant_terminal :: (DP_Problem pr m s a num, Show s, Show a) => pr -> Bool
invariant_terminal pr =
  flip all (dp_terminal_states pr) $ \st ->
    case Set.member st (dp_states pr) of
      True -> True
      False -> error $ "State " ++ show st ++ " is not a valid state"

-- Policy returns valid actions
invariant_policy_actions :: (DP_Problem pr m s a num, Ord a, Show s, Show a) => P s a -> pr -> Bool
invariant_policy_actions p pr =
  flip all (dp_states pr) $ \s ->
    flip all (dp_action pr p s) $ \(a, prob) ->
      case Set.member a (dp_actions pr s) of
        True -> True
        False -> error $ "Policy from state " ++ show s ++ " leads to invalid action " ++ show a

-- Policy return valid probabilities
invariant_policy_prob :: (DP_Problem pr m s a num, Ord a, Show s, Show a) => P s a -> pr -> Bool
invariant_policy_prob p pr =
  flip all (dp_states pr) $ \s ->
    let
      as = Set.toList (dp_action pr p s)
    in
    case sum $ map snd as of
      1 -> True
      0 | null as -> True
      x -> error $ "Policy state " ++ show s ++ " probabilities sum up to " ++ show x

invariant :: (DP_Problem pr m s a num, Show s, Show a, Ord a) => pr -> Bool
invariant pr = all ($ pr) [
    invariant_probable_actions
  , invariant_closed_transition
  , invariant_terminal
  , invariant_policy_actions (uniformGenericPolicy pr)
  , invariant_policy_prob (uniformGenericPolicy pr)
  , invariant_no_dead_states
  ]

policy_eq :: (Eq a, DP_Problem pr m s a num) => pr -> P s a -> P s a -> Bool
policy_eq pr p1 p2 = all (\s -> (dp_action pr p1 s) == (dp_action pr p2 s)) (dp_states pr)

-- instance (DP_Problem pr m s a num) => DP_Policy pr m (GenericPolicy s a) s a num where
--   dp_action GenericPolicy{..} _ s = _p_map ! s

uniformGenericPolicy :: (Ord a, DP_Problem pr m s a num) => pr -> P s a
uniformGenericPolicy pr =
  HashMap.fromList $ flip map (Set.toList (dp_states pr)) $ \s ->
    let
      as = dp_actions pr s
    in
    (s, Set.map (\a -> (a, 1%(toInteger $ length as))) as)



{-
    _    _
   / \  | | __ _
  / _ \ | |/ _` |
 / ___ \| | (_| |
/_/   \_\_|\__, |
           |___/
-}


data EvalOpts num s a = EvalOpts {
    eo_gamma :: num
  -- ^ Forgetness
  , eo_etha :: num
  -- ^ policy evaluation precision
  , eo_max_iter :: Int
  -- ^ policy evaluation iteration limit, [1..maxBound]
  -- , eo_floating_precision :: Double
  -- , eo_debug :: (StateVal num s, GenericPolicy s a) -> IO ()
  } --deriving(Show)

defaultOpts :: (Fractional num) => EvalOpts num s a
defaultOpts = EvalOpts {
    eo_gamma = 0.9
  , eo_etha = 0.1
  , eo_max_iter = 10^3
  -- , eo_floating_precision = 1/10^9
  -- , eo_debug = error "no debug specified"
  }

data EvalState num s = EvalState {
    _es_delta :: num
  , _es_v :: Map s num
  , _es_v' :: Map s num
  , _es_iter :: Int
  } deriving(Show)

makeLenses ''EvalState

initEvalState :: (Fractional num) => StateVal num s -> EvalState num s
initEvalState StateVal{..} = EvalState 0 v_map v_map 0

-- | Iterative policy evaluation algorithm
-- Figure 4.1, pg.86.
policy_eval :: (DP_Problem pr m s a num)
  => pr -> P s a -> EvalOpts num s a -> StateVal num s -> m (StateVal num s)
policy_eval pr p EvalOpts{..} v = do
  let sum l f = List.sum <$> forM (Set.toList l) f

  StateVal . view es_v <$> do
    flip execStateT (initEvalState v) $ loop $ do

      i <- use es_iter
      when (i > eo_max_iter-1) $ do
        break ()

      es_delta %= const 0

      forM_ (dp_states pr) $ \s -> do
        v_s <- uses es_v (!s)
        v's <- do
          sum (dp_action pr p s) $ \(a, fromRational -> pa) -> do
            (pa*) <$> do
              sum (dp_transitions pr s a) $ \(s', fromRational -> p) -> do
                v_s' <- uses es_v (!s')
                pure $ p * ((dp_reward pr s a s') + eo_gamma * (v_s'))

        es_v' %= (Map.insert s v's)
        es_delta %= (`max`(abs (v's - v_s)))

      d <- use es_delta
      when (d < eo_etha) $ do
        break ()

      v' <- use es_v'
      es_v %= const v'

      es_iter %= (+1)

policy_action_value :: (DP_Problem pr m s a num) => pr -> s  -> a -> EvalOpts num s a -> StateVal num s -> num
policy_action_value pr s a EvalOpts{..} StateVal{..} =
  List.sum $
  flip map (Set.toList $ dp_transitions pr s a) $ \(s', fromRational -> p) ->
    p * ((dp_reward pr s a s') + eo_gamma * (v_map ! s'))

policy_improve :: (DP_Problem pr m s a num, Ord a)
  => pr -> EvalOpts num s a -> StateVal num s -> m (P s a)
policy_improve pr eo@EvalOpts{..} v@StateVal{..} = do
  let sum l f = List.sum <$> forM (Set.toList l) f
  flip execStateT mempty $ do

    forM_ (dp_states pr) $ \s -> do
      (maxv, maxa) <- do
        foldlM (\(val,maxa) a -> do
                  pi_s <- pure $ policy_action_value pr s a eo v
                  return $
                    if Set.null maxa then
                      (pi_s, Set.singleton a)
                    else
                      if pi_s > val then
                        -- GT
                        (pi_s, Set.singleton a)
                      else
                        if pi_s < val then
                          --LT
                          (val,maxa)
                        else
                          -- EQ
                          (val, Set.insert a maxa)
               ) (0, Set.empty) (dp_actions pr s)

      let nmax = toInteger (Set.size maxa)
      modify $ HashMap.insert s (Set.map (\a -> (a,1%nmax)) maxa)


policy_iteraton_step :: (DP_Problem pr m s a num, Ord a)
  => pr -> P s a -> StateVal num s -> EvalOpts num s a -> m (StateVal num s, P s a)
policy_iteraton_step pr p v eo = do
  v' <- policy_eval pr p eo v
  p' <- policy_improve pr eo v'
  return (v',p')

-- data PolicyContainer num p s a = APolicy p | GPolicy (GenericPolicy s a)

-- withAnyPolicy :: (Monad m)
--   => pr -> PolicyContainer num p s a -> (forall p1 . p1 -> m x) -> m x
-- withAnyPolicy pr ap handler = do
--   case ap of
--     APolicy p -> handler p
--     GPolicy gp -> handler gp

policy_iteraton :: (DP_Problem pr m s a num, Ord a)
  => pr -> P s a -> StateVal num s -> EvalOpts num s a -> m (StateVal num s, P s a)
policy_iteraton pr p v eo = do
  (v', p') <-
    flip execStateT (v, p) $ do
    loop $ do
      (v,p) <- get
      (v', p') <- lift $ lift $ policy_iteraton_step pr p v eo
      lift $ lift $ dp_trace pr v' p'
      put (v', p')
      when (policy_eq pr p p') $ do
        break ()
  return (v',p')



