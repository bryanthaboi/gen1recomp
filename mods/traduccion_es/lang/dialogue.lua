-- Script text
--
-- Keyed by the original text label. Dialogue arrives automatically: the
-- mod decodes the official Spanish script out of the EUR dump in the
-- player's imports/ folder, so ROM lines never need entries here. An
-- entry filled in wins over the automatic layer, which makes this the
-- place to hand-fix a line.
--
-- The entries below are NOT ROM lines: they are the hand-ported cutscene
-- literals data/scripts/ feeds to show_text, which looks each one up in
-- the merged text table (by its English wording) before falling back to
-- the literal -- so overriding the wording translates the line.

return {
  ["So you've come to\nshut down my\noperation?\f"] =
    "¿Así que vienes a\ncerrar mi\noperación?\f",
  ["Gah! Even the\nCHIEF is no match\nfor you!\f"] =
    "¡Agh! ¡Ni el JEFE\npuede contigo!\f",
  ["You look tired!\nYou should take a\nquick nap!"] =
    "¡Pareces cansado!\n¡Échate una\nsiestecita!",
  ["Don't give up!"] = "¡No te rindas!",
  ["Thank you so\nmuch!"] = "¡Muchísimas\ngracias!",
  ["That's PROF.OAK's\nlast Pokémon!"] =
    "¡Es el último\nPokémon de\nPROF.OAK!",
  ["OAK: So you want\nto test your\nskills on me?\f"] =
    "OAK: ¿Quieres\nprobar tu nivel\nconmigo?\f",
  ["OAK: Impressive!\nYou truly are a\nPOKéMON MASTER!"] =
    "OAK: ¡Increíble!\n¡Eres un auténtico\nMAESTRO POKéMON!",
}
