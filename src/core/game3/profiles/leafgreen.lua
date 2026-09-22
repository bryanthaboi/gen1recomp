local row = {}
for k, v in pairs(require("src.core.game3.profiles.firered")) do row[k] = v end
row.id = "leafgreen"
row.label = "LeafGreen"
return row
