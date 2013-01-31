{-# LANGUAGE OverloadedStrings #-}

module Magic.M13 where

import Magic.Types
import Magic.ObjectTypes
import Magic.Target
import Magic.Utils
import Magic.Core
import Magic.Events

import Control.Applicative
import Control.Monad (void)
import Data.Label.Pure (get)
import Data.Label.PureM ((=:), asks)


instantSpeed :: ObjectRef -> PlayerRef -> View Bool
instantSpeed rSelf rActivator =
  case rSelf of
    (Hand rp, _) -> return (rp == rActivator)
    _            -> return False

sorcerySpeed :: ObjectRef -> PlayerRef -> View Bool
sorcerySpeed rSelf rp = (&&) <$> instantSpeed rSelf rp <*> myMainPhase
  where
    myMainPhase = do
      ap <- asks activePlayer
      as <- asks activeStep
      return (ap == rp && as == MainPhase)

-- | The effect of playing a permanent without targets that uses the stack.
playPermanentEffect :: ObjectRef -> PlayerRef -> Magic ()
playPermanentEffect rSelf _ = do
    effect <- view (willMoveToStack rSelf (pure resolvePermanent))
    _ <- executeEffect effect
    return ()
  where
    resolvePermanent _source = return ()

stackingPlayAbility :: ManaPool -> [AdditionalCost] -> Ability
stackingPlayAbility mc ac rSelf rActivator =
  ClosedAbility
    { _available       = do
      self <- asks (object rSelf)
      if hasTypes instantType self || Flash `elem` get staticKeywordAbilities self
        then instantSpeed rSelf rActivator
        else sorcerySpeed rSelf rActivator
    , _manaCost        = mc
    , _additionalCosts = ac
    , _effect          = playPermanentEffect rSelf rActivator
    , _isManaAbility   = False
    }

ajani'sSunstriker :: Card
ajani'sSunstriker = mkCard $ do
  name      =: Just "Ajani's Sunstriker"
  types     =: creatureType
  power     =: Just 2
  toughness =: Just 2
  play     =: (Just $ \rSelf rActivator ->
    ClosedAbility
      { _available       = sorcerySpeed rSelf rActivator
      , _manaCost        = [Just White, Just White]
      , _additionalCosts = []
      , _effect          = playPermanentEffect rSelf rActivator
      , _isManaAbility   = False
      })
  staticKeywordAbilities =: [Lifelink]

searingSpear :: Card
searingSpear = mkCard $ do
  name  =: Just "Searing Spear"
  types =: instantType
  play  =: (Just $ \rSelf rActivator ->
    ClosedAbility
      { _available = instantSpeed rSelf rActivator
      , _manaCost = [Nothing, Just Red]
      , _additionalCosts = []
      , _effect = searingSpearEffect rSelf rActivator
      , _isManaAbility = False
      })

searingSpearEffect :: ObjectRef -> PlayerRef -> Magic ()
searingSpearEffect rSelf rActivator = do
  let ok t = case t of
              TargetObject r@(Battlefield, _) -> hasTypes creatureType <$> asks (object r)
              TargetPlayer _                  -> return True
              _                               -> return False
  ts <- askMagicTargets rActivator (singleTarget <?> ok)
  let f :: Target -> Object -> Magic ()
      f t source = void $ executeEffect $ case t of
        TargetObject r -> Will (DamageObject source r 3 False True)
        TargetPlayer r -> Will (DamagePlayer source r 3 False True)
  void (view (willMoveToStack rSelf (f <$> ts)) >>= executeEffect)
