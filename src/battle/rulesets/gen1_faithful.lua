-- Default ruleset: preserve Gen 1 behavior, including the famous quirks.

return {
  name = "gen1_faithful",
  -- accuracy roll is rand(0..255) < floor(acc*255/100): a 100%-accurate
  -- move still misses on a roll of 255 (the 1/256 miss)
  oneIn256Miss = true,
  -- critical hits use base speed (not current speed) and ignore stat stages
  critUsesBaseSpeed = true,
  critIgnoresStages = true,
  -- damage random factor r in [217,255], damage = damage * r / 255
  randMin = 217,
  randMax = 255,
  -- Focus Energy famously QUARTERS the crit rate instead of x4
  focusEnergyBug = true,
  -- Wild/trainer enemies never spend PP (DecrementPP only touches the
  -- player side in pokered). They therefore never Struggle from empty PP.
  enemyUnlimitedPP = true,
  -- Gen 1 Hyper Beam: no recharge when the target faints (or its
  -- substitute breaks).  Set false to always recharge like Gen 2+.
  hyperBeamSkipRechargeOnKO = true,
  -- Gen 1 runs HandlePoisonBurnLeechSeed right after each side's move
  -- (core.asm:426-464): poison/burn/leech seed tick before the slower
  -- mon acts, not in an end-of-round sweep like Gen 3+.
  residualAfterMove = true,
  -- engine/battle/effects.asm:498,689
  badgeBoostReapplyBug = true,
}
