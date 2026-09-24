#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Json = require("src.link.Json")
local MysteryGift = require("src.core.game3.mystery_gift")

local FIXTURE_PUB = "58c5b57e548789c3d231a9537f172bcf515a39b053f58a90c7b0096967a746ba"
local FIXTURE_BODY = [==[{"v":1,"payload":"{\"cards\":[{\"bgType\":2,\"bodyText\":[\"Thank you for using the MYSTERY\",\"GIFT System.\",\"There is a ticket here for you.\",\"It is for use at VERMILION CITY port.\"],\"flagId\":1001,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"haveFlags\":[680,754,755],\"item\":370,\"kind\":\"item\",\"quantity\":1,\"setFlags\":[2122,680]},\"iconSpecies\":0,\"idNumber\":1,\"key\":\"mystic_ticket\",\"maxStamps\":0,\"sendType\":0,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"MYSTIC TICKET\",\"type\":0},{\"bgType\":7,\"bodyText\":[\"A mythical POKéMON has been\",\"sent to you from the\",\"POKéMON CENTER.\",\"Please take good care of it.\"],\"flagId\":1007,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"kind\":\"mon\",\"level\":10,\"moves\":{\"1\":1},\"otId\":20078,\"otName\":\"AURA\",\"species\":151},\"iconSpecies\":151,\"idNumber\":7,\"key\":\"mew\",\"maxStamps\":0,\"sendType\":0,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"MEW\",\"type\":0},{\"bgType\":4,\"bodyText\":[\"Thank you for using the STAMP CARD\",\"System.\",\"Trade with other TRAINERS to fill\",\"your STAMP CARD.\"],\"flagId\":1004,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"kind\":\"none\"},\"iconSpecies\":0,\"idNumber\":4,\"key\":\"stamp_card\",\"maxStamps\":7,\"sendType\":1,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"STAMP CARD\",\"type\":1}],\"issued\":0,\"news\":[{\"bgType\":1,\"bodyText\":[\"Welcome to the POKéMON\",\"WIRELESS CLUB news.\",\"Look for new WONDER CARDS.\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"],\"id\":1,\"key\":\"launch_news\",\"sendType\":0,\"titleText\":\"WONDER NEWS\"}],\"v\":1}","sig":"44aa8146ee6d745efe81afc3427aaf84d07b4c64bacb6922c8d9ff27fa779e3d628c55cd623ab49c9afc2fc84f02be8942350cae4ae08c1e4e01955a671d7009","key":"58c5b57e548789c3d231a9537f172bcf515a39b053f58a90c7b0096967a746ba"}]==]

local REAL_PUB = MysteryGift.GIFT_PUBKEY

local function fixtureFeed()
  return Json.decode(FIXTURE_BODY)
end

local function withKey(pub, fn)
  local saved = MysteryGift.GIFT_PUBKEY
  MysteryGift.GIFT_PUBKEY = pub
  local ok, a, b = pcall(fn)
  MysteryGift.GIFT_PUBKEY = saved
  assert(ok, a)
  return a, b
end

local function fakeTransport(replies)
  local t = { begun = {}, released = 0, canceled = 0 }
  function t:begin(req)
    self.begun[#self.begun + 1] = req
    return #self.begun
  end
  function t:poll(handle)
    local r = replies[handle]
    if type(r) == "table" and r.pending and r.pending > 0 then
      r.pending = r.pending - 1
      return { status = "pending" }
    end
    return r or { status = "error", err = "unreachable" }
  end
  function t:release() self.released = self.released + 1 end
  function t:cancel() self.canceled = self.canceled + 1 end
  return t
end

print("[test] 1. The client carries the owner's public key")
eq(REAL_PUB, "2cecc61cc4d4ea70fc6802a66643e659a0f2c344eec6391ccf20b434ab280ffd",
  "GIFT_PUBKEY is the triage key")
eq(MysteryGift.FEED_PATH, "/gifts/gen3", "the feed path is /gifts/gen3")

print("[test] 2. A signed feed parses")
local feed = fixtureFeed()
check(type(feed) == "table" and type(feed.payload) == "string", "the reply body decodes")
local list, why = withKey(FIXTURE_PUB, function() return MysteryGift.verifyFeed(feed) end)
check(list ~= nil, "the fixture verifies under its key: " .. tostring(why))
eq(list and #list.cards, 3, "three cards")
eq(list and #list.news, 1, "one news")
eq(list and list.cards[1].key, "mystic_ticket", "cards keep the server key")
eq(list and list.cards[2].card.titleText, "MEW", "the MEW card title")
eq(list and list.cards[2].card.bodyText[1], "A mythical POKéMON has been", "UTF-8 text survives the round trip")
eq(list and list.cards[2].card.gift.moves[1], 1, "move slots arrive as numbers")
eq(list and list.cards[2].card.gift.otId, 20078, "the OT id")
eq(list and list.cards[3].card.maxStamps, 7, "the stamp card keeps its stamp count")
eq(list and list.news[1].news.id, 1, "the news id")
eq(list and #list.news[1].news.bodyText, 10, "the news has ten body lines")
eq(list and list.news[1].label, "WONDER NEWS", "the news label is its title")

print("[test] 3. Tampering is refused")
local _, bad = MysteryGift.verifyFeed(fixtureFeed())
eq(bad, "bad_signature", "the fixture fails under the real key")
local tampered = fixtureFeed()
tampered.payload = tampered.payload:gsub('"item":370', '"item":371')
_, bad = withKey(FIXTURE_PUB, function() return MysteryGift.verifyFeed(tampered) end)
eq(bad, "bad_signature", "a changed item id fails")
local lifted = fixtureFeed()
lifted.payload = lifted.payload:gsub('"species":151', '"species":150')
_, bad = withKey(FIXTURE_PUB, function() return MysteryGift.verifyFeed(lifted) end)
eq(bad, "bad_signature", "a changed species fails")
local spaced = fixtureFeed()
spaced.payload = spaced.payload .. " "
_, bad = withKey(FIXTURE_PUB, function() return MysteryGift.verifyFeed(spaced) end)
eq(bad, "bad_signature", "a trailing byte fails")
local resigned = fixtureFeed()
resigned.sig = resigned.sig:sub(1, 127) .. (resigned.sig:sub(128) == "0" and "1" or "0")
_, bad = withKey(FIXTURE_PUB, function() return MysteryGift.verifyFeed(resigned) end)
eq(bad, "bad_signature", "a changed signature fails")
local swapped = fixtureFeed()
swapped.key = REAL_PUB
_, bad = withKey(FIXTURE_PUB, function() return MysteryGift.verifyFeed(swapped) end)
check(bad == nil, "the reply's own key field is never trusted over the baked key")
_, bad = MysteryGift.verifyFeed({ payload = feed.payload })
eq(bad, "bad_feed", "a missing signature is a bad feed")
_, bad = MysteryGift.verifyFeed({ error = "gifts_unsigned" })
eq(bad, "bad_feed", "an unsigned server reply is a bad feed")
_, bad = MysteryGift.parseFeed('{"v":2,"cards":[],"news":[]}')
eq(bad, "bad_feed", "an unknown feed version is refused")
_, bad = MysteryGift.parseFeed("not json")
eq(bad, "bad_feed", "garbage is refused")
local skipped = MysteryGift.parseFeed(
  '{"v":1,"issued":1,"cards":[{"flagId":0,"idNumber":9,"type":0},{"flagId":2000,"idNumber":8,"type":0}],'
  .. '"news":[{"id":0}]}')
eq(skipped and #skipped.cards, 0, "cards outside the Wonder Card flag range are dropped")
eq(skipped and #skipped.news, 0, "news without an id is dropped")

print("[test] 4. fetchOnline / pollOnline")
local okT = fakeTransport({ { status = "ok", code = 200, body = FIXTURE_BODY, pending = 2 } })
local job = MysteryGift.fetchOnline({ transport = okT })
eq(job.status, "pending", "the fetch starts")
local req = okT.begun[1]
check(req ~= nil and req.method == "GET", "it is a GET")
check(req ~= nil and req.url:sub(-#"/gifts/gen3") == "/gifts/gen3", "to /gifts/gen3: " .. tostring(req and req.url))
check(req ~= nil and req.headers["x-sync-token"] == nil, "without sync credentials")
eq(req and req.maxSeconds, 10, "with a ten second budget")
eq((MysteryGift.pollOnline(job)), "pending", "pending while the transport is")
eq((MysteryGift.pollOnline(job)), "pending", "still pending")
local status, result = withKey(FIXTURE_PUB, function() return MysteryGift.pollOnline(job) end)
eq(status, "ok", "the verified feed arrives")
eq(result and #result.cards, 3, "with its cards")
eq(okT.released, 1, "the handle is released")
status = MysteryGift.pollOnline(job)
eq(status, "ok", "a finished job keeps its answer")

local forged = MysteryGift.fetchOnline({ transport = fakeTransport({ { status = "ok", code = 200, body = FIXTURE_BODY } }) })
status, result = MysteryGift.pollOnline(forged)
eq(status, "error", "a feed signed by another key is an error")
eq(result, "bad_signature", "reported as a bad signature")

local down = MysteryGift.fetchOnline({ transport = fakeTransport({ { status = "error", err = "could not connect" } }) })
status, result = MysteryGift.pollOnline(down)
eq(status, "error", "no network is an error")
eq(result, "offline", "reported as offline")

local unsigned = MysteryGift.fetchOnline({ transport = fakeTransport({
  { status = "ok", code = 503, body = '{"error":"gifts_unsigned"}' } }) })
status, result = MysteryGift.pollOnline(unsigned)
eq(result, "server", "a 503 from the server is a server error")

local noTransport = { begin = function() return nil end, poll = function() return { status = "error" } end }
status, result = MysteryGift.pollOnline(MysteryGift.fetchOnline({ transport = noTransport }))
eq(result, "offline", "no network transport is offline")

local slowT = fakeTransport({ { status = "ok", code = 200, body = FIXTURE_BODY, pending = 99 } })
local slow = MysteryGift.fetchOnline({ transport = slowT })
MysteryGift.cancelOnline(slow)
eq(slowT.canceled, 1, "cancel reaches the transport")
status, result = MysteryGift.pollOnline(slow)
eq(result, "canceled", "and the job reads canceled")

print("[test] 5. One claim per card per save")
local save = {}
local sess = MysteryGift.sessionFromSave(save)
local mewCard = list.cards[2].card
check(not MysteryGift.hasClaimedCard(sess, mewCard), "a fresh save has not claimed the MEW card")
check(MysteryGift.claimCard(sess, mewCard), "claiming records it")
check(MysteryGift.hasClaimedCard(sess, mewCard), "the claim reads back")
check(MysteryGift.hasClaimedCard(sess, 7), "by idNumber too")
check(not MysteryGift.hasClaimedCard(sess, list.cards[1].card), "other cards stay open")
MysteryGift.claimCard(sess, mewCard)
eq(#MysteryGift.ensure(sess).claims.cards, 1, "claiming twice keeps one record")
MysteryGift.clearCardAndRelated(sess)
check(MysteryGift.hasClaimedCard(sess, mewCard), "tossing the card does not forget the claim")
check(MysteryGift.applyToSave(sess, save), "the record writes back")
local reloaded = MysteryGift.sessionFromSave(save)
check(MysteryGift.hasClaimedCard(reloaded, mewCard), "the claim survives a save reload")
check(MysteryGift.claimNews(reloaded, list.news[1].news), "news claims record")
check(MysteryGift.hasClaimedNews(reloaded, 1), "news claims read back by id")
check(not MysteryGift.hasClaimedNews(reloaded, 2), "other news stays open")
local legacy = MysteryGift.sessionFromSave({})
MysteryGift.saveCard(legacy, list.cards[1].card)
check(MysteryGift.hasClaimedCard(legacy, 1), "a card already saved counts as claimed")
check(not MysteryGift.hasClaimedCard(legacy, 0), "id 0 is never claimed")

print("[test] 6. Text limits count characters, not bytes")
local forty = string.rep("é", 40)
local card = MysteryGift.normalizeCard({ titleText = forty .. "X", flagId = 1000, idNumber = 1 })
eq(card.titleText, forty, "forty two-byte characters survive whole")
card = MysteryGift.normalizeCard({ titleText = string.rep("A", 45) })
eq(#card.titleText, 40, "ASCII still clamps at forty")

print("[test] 7. No drop-in or built-in source path is left")
eq(MysteryGift.sources, nil, "MysteryGift.sources is gone")
eq(MysteryGift.loadDropIn, nil, "the drop-in loader is gone")
eq(MysteryGift.parse, nil, "the drop-in parser is gone")
check(type(MysteryGift.builtins) == "function", "builtins stay as the server preset reference")

if failed == 0 then
  print("PASS game3_gift_feed")
else
  print("FAIL game3_gift_feed failures=" .. failed)
  os.exit(1)
end
