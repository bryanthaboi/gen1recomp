-- Gallery entry: reshape Oak's intro speech with extra questions, sprite
-- swaps (oak / rival / player / pokemon / a custom image), and answers
-- that land in mod.save.
--
-- Uses hooks:wrap("intro.oak_speech.build") plus intro.oak_speech.answered.

return function(mod)
  local toastPic = mod.path .. "/assets/toast_kid.png"

  mod.hooks:wrap("intro.oak_speech.build", function(next, steps, speech)
    steps = next(steps, speech)

    -- after oak says hello, immediately derail
    mod.ui.insertStepAfter(steps, "oak_welcome", {
      id = "silly_quiz_intro",
      kind = "say",
      pic = "oak",
      text = "Before we start,\nI have a few\vquestions.\fImportant ones.\nScientific ones.",
    })

    mod.ui.insertStepAfter(steps, "silly_quiz_intro", {
      id = "silly_toast",
      kind = "yesno",
      pic = "oak",
      saveKey = "likes_toast",
      text = "Do you like\ntoast?",
    })

    -- brand new sprite mid-speech
    mod.ui.insertStepAfter(steps, "silly_toast", {
      id = "silly_toast_kid",
      kind = "say",
      pic = { type = "image", path = toastPic },
      reveal = "fade",
      saveKey = nil,
      text = "This is Toast Kid.\nHe is not a\vPOKéMON.\fHe just showed up\none day.\fAnyway.",
    })

    -- existing mon with a wipe + cry, parked after the real demo mon
    mod.ui.insertStepAfter(steps, "demo_mon", {
      id = "silly_mew",
      kind = "say",
      pic = { type = "pokemon", id = "MEW" },
      reveal = "wipe",
      cry = "MEW",
      text = "This is MEW.\nPlease do not\vtell anyone\vI showed you.",
    })

    mod.ui.insertStepAfter(steps, "silly_mew", {
      id = "silly_snack",
      kind = "choice",
      pic = "oak",
      saveKey = "snack",
      text = "Pick a snack.\nThis goes on\vyour permanent\vrecord.",
      choices = { "BERRIES", "LEFTOVERS", "OLD ROD" },
    })

    -- swap to rival pic for a loaded question before naming him
    mod.ui.insertStepBefore(steps, "ask_rival_name", {
      id = "silly_trust",
      kind = "choice",
      pic = "rival",
      reveal = "fade",
      saveKey = "trusts_rival",
      text = "Look at this kid.\nTrustworthy?",
      choices = { "SURE", "NO" },
      values = { true, false },
    })

    -- player pic for one last bit after both names are set
    mod.ui.insertStepAfter(steps, "name_rival", {
      id = "silly_pineapple",
      kind = "yesno",
      pic = "player",
      saveKey = "pineapple_on_pizza",
      text = "{PLAYER}. Be honest.\nPineapple on\vpizza?",
    })

    mod.ui.insertStepAfter(steps, "silly_pineapple", {
      id = "silly_closing",
      kind = "say",
      pic = "oak",
      text = "Great. Terrible.\nI have notes.\fLet's pretend this\nwas normal.",
    })

    return steps
  end)

  -- every answered step with a saveKey lands in mod.save (and therefore
  -- save.modData[mod.id] once the slot is written)
  mod.events:on("intro.oak_speech.answered", function(ev)
    if not ev.saveKey then return end
    mod.save:set(ev.saveKey, ev.value)
    mod.log:info("intro answer %s = %s", tostring(ev.saveKey), tostring(ev.value))
  end)

  mod.events:on("intro.oak_speech.finished", function(ev)
    local answers = ev.answers or {}
    for key, value in pairs(answers) do
      if mod.save:get(key) == nil then
        mod.save:set(key, value)
      end
    end
    mod.save:set("quiz_done", true)
    mod.log:info("silly oak quiz done")
  end)
end
