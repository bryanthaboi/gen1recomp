local P = require("src.render.CompanionPreference")
for _, destination in ipairs({ "auto", "handheld", "secondary" }) do
  for _, sizing in ipairs({ "fit", "integer" }) do
    local d,s,f=P.explicit(destination..":"..sizing)
    assert(d==destination and s==sizing and f==nil)
    for _, filter in ipairs({ "auto", "nearest", "bilinear", "sharp" }) do
      d,s,f=P.explicit(destination..":"..sizing..":"..filter)
      assert(d==destination and s==sizing and f==filter)
    end
  end
end
for _, value in ipairs({ "auto", "handheld", "secondary", "handheld:cover", "secondary:cover",
    "unknown:integer", "secondary:fit:unknown", "secondary:integer:extra:auto",
    "secondary:cover:auto", "secondary:integer:", "handheld:private", "discover" }) do
  assert(P.explicit(value)==nil,"legacy/unknown preference must not opt in: "..value)
end
assert(P.explicit(nil)==nil and P.explicit(false)==nil and P.explicit({})==nil)
print("companion preferences: explicit opt-in and unknown/legacy isolation passed")
