-- Layout, flex, text, image, and ARIA enums used across FlexLove.
-- Extracted from utils so utils stays under its LOC budget; re-exported as
-- `utils.enums` for backward compatibility.

local enums = {
  ---@enum TextAlign
  TextAlign = { START = "start", CENTER = "center", END = "end", JUSTIFY = "justify" },
  ---@enum TextAlignVertical
  TextAlignVertical = { START = "start", CENTER = "center", END = "end" },
  ---@enum Positioning
  Positioning = { ABSOLUTE = "absolute", RELATIVE = "relative", FLEX = "flex", GRID = "grid" },
  ---@enum FlexDirection
  FlexDirection = {
    HORIZONTAL = "horizontal",
    VERTICAL = "vertical",
    ROW = "row",
    COLUMN = "column",
    HORIZONTAL_REVERSE = "horizontal-reverse",
    VERTICAL_REVERSE = "vertical-reverse",
    ROW_REVERSE = "row-reverse",
    COLUMN_REVERSE = "column-reverse",
  },
  ---@enum JustifyContent
  JustifyContent = {
    FLEX_START = "flex-start",
    CENTER = "center",
    SPACE_AROUND = "space-around",
    FLEX_END = "flex-end",
    SPACE_EVENLY = "space-evenly",
    SPACE_BETWEEN = "space-between",
  },
  ---@enum JustifySelf
  JustifySelf = {
    AUTO = "auto",
    FLEX_START = "flex-start",
    CENTER = "center",
    FLEX_END = "flex-end",
    SPACE_AROUND = "space-around",
    SPACE_EVENLY = "space-evenly",
    SPACE_BETWEEN = "space-between",
  },
  ---@enum AlignItems
  AlignItems = {
    STRETCH = "stretch",
    FLEX_START = "flex-start",
    FLEX_END = "flex-end",
    CENTER = "center",
    BASELINE = "baseline",
  },
  ---@enum AlignSelf
  AlignSelf = {
    AUTO = "auto",
    STRETCH = "stretch",
    FLEX_START = "flex-start",
    FLEX_END = "flex-end",
    CENTER = "center",
    BASELINE = "baseline",
  },
  ---@enum AlignContent
  AlignContent = {
    STRETCH = "stretch",
    FLEX_START = "flex-start",
    FLEX_END = "flex-end",
    CENTER = "center",
    SPACE_BETWEEN = "space-between",
    SPACE_AROUND = "space-around",
  },
  ---@enum FlexWrap
  FlexWrap = { NOWRAP = "nowrap", WRAP = "wrap", WRAP_REVERSE = "wrap-reverse" },
  ---@enum TextSize
  TextSize = {
    XXS = "xxs",
    XS = "xs",
    SM = "sm",
    MD = "md",
    LG = "lg",
    XL = "xl",
    XXL = "xxl",
    XL3 = "3xl",
    XL4 = "4xl",
  },
  ---@enum ImageRepeat
  ImageRepeat = {
    NO_REPEAT = "no-repeat",
    REPEAT = "repeat",
    REPEAT_X = "repeat-x",
    REPEAT_Y = "repeat-y",
    SPACE = "space",
    ROUND = "round",
  },

  ---@enum ARIA Role (accessibility roles for screen readers)
  ARIA = {
    -- Widget roles
    BUTTON = "button",
    CHECKBOX = "checkbox",
    LINK = "link",
    MENUITEM = "menuitem",
    MENUITEMCHECKBOX = "menuitemcheckbox",
    MENUITEMRADIO = "menuitemradio",
    PROGRESSBAR = "progressbar",
    RADIO = "radio",
    SCROLLBAR = "scrollbar",
    SLIDER = "slider",
    SPINBUTTON = "spinbutton",
    SWITCH = "switch",
    TAB = "tab",
    TABLIST = "tablist",
    TABPANEL = "tabpanel",
    TEXTBOX = "textbox",
    TOOLTIP = "tooltip",
    TREEITEM = "treeitem",
    COMBOBOX = "combobox",
    GRID = "grid",
    GRIDCELL = "gridcell",
    LISTBOX = "listbox",
    LISTITEM = "listitem",
    MENU = "menu",
    MENUBAR = "menubar",
    TREE = "tree",
    TREEGRID = "treegrid",
    WINDOW = "window",
    DIALOG = "dialog",
    ALERTDIALOG = "alertdialog",

    -- Landmark roles
    BANNER = "banner",
    COMPLEMENTARY = "complementary",
    CONTENTINFO = "contentinfo",
    FORM = "form",
    MAIN = "main",
    NAVIGATION = "navigation",
    REGION = "region",
    SEARCH = "search",

    -- Live region roles
    ALERT = "alert",
    LOG = "log",
    MARQUEE = "marquee",
    STATUS = "status",
    TIMERTIME = "timer",

    -- Document structure roles
    ARTICLE = "article",
    BLOCKQUOTEBLOCKQUOTE = "blockquote",
    CAPTION = "caption",
    CODE = "code",
    DEFINITION = "definition",
    DELETED = "deletion",
    DIRECTORY = "directory",
    DIVISION = "division",
    EMphasis = "emphasis",
    HEADING = "heading",
    INSERTED = "insertion",
    LIST = "list",
    MARK = "mark",
    MATH = "math",
    NONE = "none",
    PARAGRAPH = "paragraph",
    PRESENTATION = "presentation",
    SEPARATOR = "separator",
    STRONG = "strong",
    SUBSCRIPT = "subscript",
    SUPERSCRIPT = "superscript",
    TERM = "term",
    TIME = "time",
    VARIABLE = "variable",
  },
}

return { enums = enums }
