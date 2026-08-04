--- Utility module for parsing and evaluating CSS-like calc() expressions
--- Supports arithmetic operations (+, -, *, /) with mixed units (px, %, vw, vh)
---@class Calc
local Calc = {}

--- Initialize Calc module with dependencies
---@param deps CalcDependencies Dependencies: { ErrorHandler = ErrorHandler? }
function Calc.init(deps)
  Calc._ErrorHandler = deps.ErrorHandler
end

--- Token types for lexical analysis
local TokenType = {
  NUMBER = "NUMBER",
  UNIT = "UNIT",
  PLUS = "PLUS",
  MINUS = "MINUS",
  MULTIPLY = "MULTIPLY",
  DIVIDE = "DIVIDE",
  LPAREN = "LPAREN",
  RPAREN = "RPAREN",
  EOF = "EOF",
}

--- Tokenize a calc expression string into tokens
---@param expr string The expression to tokenize (e.g., "50% - 10vw")
---@return CalcToken[]? tokens Array of tokens with type, value, unit
---@return string? error Error message if tokenization fails
local function tokenize(expr)
  local tokens = {}
  local i = 1
  local len = #expr

  while i <= len do
    local char = expr:sub(i, i)

    -- Skip whitespace
    if char:match("%s") then
      i = i + 1
    -- Number (including decimals, but NOT negative - handled separately below)
    elseif char:match("%d") or (char == "." and expr:sub(i + 1, i + 1):match("%d")) then
      local numStr = ""

      -- Parse integer and decimal parts
      while i <= len and (expr:sub(i, i):match("%d") or expr:sub(i, i) == ".") do
        numStr = numStr .. expr:sub(i, i)
        i = i + 1
      end

      local num = tonumber(numStr)
      if not num then
        return nil, "Invalid number: " .. numStr
      end

      -- Check for unit following the number
      local unitStr = ""
      while i <= len and expr:sub(i, i):match("[%a%%]") do
        unitStr = unitStr .. expr:sub(i, i)
        i = i + 1
      end

      -- Default to px if no unit
      if unitStr == "" then
        unitStr = "px"
      end

      -- Validate unit
      local validUnits = { px = true, ["%"] = true, vw = true, vh = true }
      if not validUnits[unitStr] then
        return nil, "Invalid unit: " .. unitStr
      end

      table.insert(tokens, {
        type = TokenType.NUMBER,
        value = num,
        unit = unitStr,
      })
    -- Operators
    elseif char == "+" then
      table.insert(tokens, { type = TokenType.PLUS })
      i = i + 1
    elseif char == "-" then
      -- Check if this is a negative number or subtraction
      -- It's a negative number if previous token is an operator or opening paren
      local prevToken = tokens[#tokens]
      if
        not prevToken
        or prevToken.type == TokenType.PLUS
        or prevToken.type == TokenType.MINUS
        or prevToken.type == TokenType.MULTIPLY
        or prevToken.type == TokenType.DIVIDE
        or prevToken.type == TokenType.LPAREN
      then
        -- This is a negative number, continue to number parsing
        local numStr = "-"
        i = i + 1

        -- Parse integer and decimal parts
        while i <= len and (expr:sub(i, i):match("%d") or expr:sub(i, i) == ".") do
          numStr = numStr .. expr:sub(i, i)
          i = i + 1
        end

        local num = tonumber(numStr)
        if not num then
          return nil, "Invalid number: " .. numStr
        end

        -- Check for unit following the number
        local unitStr = ""
        while i <= len and expr:sub(i, i):match("[%a%%]") do
          unitStr = unitStr .. expr:sub(i, i)
          i = i + 1
        end

        -- Default to px if no unit
        if unitStr == "" then
          unitStr = "px"
        end

        -- Validate unit
        local validUnits = { px = true, ["%"] = true, vw = true, vh = true }
        if not validUnits[unitStr] then
          return nil, "Invalid unit: " .. unitStr
        end

        table.insert(tokens, {
          type = TokenType.NUMBER,
          value = num,
          unit = unitStr,
        })
      else
        -- This is subtraction operator
        table.insert(tokens, { type = TokenType.MINUS })
        i = i + 1
      end
    elseif char == "*" then
      table.insert(tokens, { type = TokenType.MULTIPLY })
      i = i + 1
    elseif char == "/" then
      table.insert(tokens, { type = TokenType.DIVIDE })
      i = i + 1
    elseif char == "(" then
      table.insert(tokens, { type = TokenType.LPAREN })
      i = i + 1
    elseif char == ")" then
      table.insert(tokens, { type = TokenType.RPAREN })
      i = i + 1
    else
      return nil, "Unexpected character: " .. char
    end
  end

  table.insert(tokens, { type = TokenType.EOF })
  return tokens
end

--- Parser for calc expressions using recursive descent
---@class Parser
---@field tokens CalcToken[] Array of tokens
---@field pos number Current token position
local Parser = {}
Parser.__index = Parser

--- Create a new parser
---@param tokens CalcToken[] Array of tokens
---@return Parser
function Parser.new(tokens)
  local self = setmetatable({}, Parser)
  self.tokens = tokens
  self.pos = 1
  return self
end

--- Get current token
---@return CalcToken token Current token
function Parser:current()
  return self.tokens[self.pos]
end

--- Advance to next token
function Parser:advance()
  self.pos = self.pos + 1
end

--- Parse expression (handles + and -)
---@return CalcASTNode ast Abstract syntax tree node
function Parser:parseExpression()
  local left = self:parseTerm()

  while self:current().type == TokenType.PLUS or self:current().type == TokenType.MINUS do
    local op = self:current().type
    self:advance()
    local right = self:parseTerm()
    left = {
      type = op == TokenType.PLUS and "add" or "subtract",
      left = left,
      right = right,
    }
  end

  return left
end

--- Parse term (handles * and /)
---@return CalcASTNode ast Abstract syntax tree node
function Parser:parseTerm()
  local left = self:parseFactor()

  while self:current().type == TokenType.MULTIPLY or self:current().type == TokenType.DIVIDE do
    local op = self:current().type
    self:advance()
    local right = self:parseFactor()
    left = {
      type = op == TokenType.MULTIPLY and "multiply" or "divide",
      left = left,
      right = right,
    }
  end

  return left
end

--- Parse factor (handles numbers and parentheses)
---@return CalcASTNode ast Abstract syntax tree node
function Parser:parseFactor()
  local token = self:current()

  if token.type == TokenType.NUMBER then
    self:advance()
    return {
      type = "number",
      value = token.value,
      unit = token.unit,
    }
  elseif token.type == TokenType.LPAREN then
    self:advance()
    local expr = self:parseExpression()
    if self:current().type ~= TokenType.RPAREN then
      error("Expected closing parenthesis")
    end
    self:advance()
    return expr
  else
    error("Unexpected token: " .. token.type)
  end
end

--- Parse the tokens into an AST
---@return CalcASTNode ast Abstract syntax tree
function Parser:parse()
  local ast = self:parseExpression()
  if self:current().type ~= TokenType.EOF then
    error("Unexpected tokens after expression")
  end
  return ast
end

--- Create a calc expression object that can be resolved later
--- This is the main API function that users call
---@param expr string The calc expression (e.g., "50% - 10vw")
---@return CalcObject calcObject A calc expression object with AST
function Calc.new(expr)
  -- Tokenize
  local tokens, err = tokenize(expr)
  if not tokens then
    if Calc._ErrorHandler then
      Calc._ErrorHandler:warn("Calc", "VAL_006", {
        expression = expr,
        error = err,
      })
    end
    -- Return a fallback calc object that resolves to 0
    return {
      _isCalc = true,
      _expr = expr,
      _ast = nil,
      _error = err,
    }
  end

  -- Parse
  local parser = Parser.new(tokens)
  local success, ast = pcall(function()
    return parser:parse()
  end)

  if not success then
    if Calc._ErrorHandler then
      Calc._ErrorHandler:warn("Calc", "VAL_006", {
        expression = expr,
        error = ast, -- ast contains error message on failure
      })
    end
    -- Return a fallback calc object that resolves to 0
    return {
      _isCalc = true,
      _expr = expr,
      _ast = nil,
      _error = ast,
    }
  end

  return {
    _isCalc = true,
    _expr = expr,
    _ast = ast,
  }
end

--- Check if a value is a calc expression
---@param value any The value to check
---@return boolean isCalc True if value is a calc expression
function Calc.isCalc(value)
  return type(value) == "table" and value._isCalc == true
end

--- Resolve a calc expression to pixel value
---@param calcObj CalcObject The calc expression object
---@param viewportWidth number Viewport width in pixels
---@param viewportHeight number Viewport height in pixels
---@param parentSize number? Parent dimension for percentage units
---@return number resolvedValue Resolved pixel value
function Calc.resolve(calcObj, viewportWidth, viewportHeight, parentSize)
  if not calcObj._ast then
    -- Error during parsing, return 0
    return 0
  end

  --- Evaluate AST node recursively
  ---@param node table AST node
  ---@return number value Evaluated value in pixels
  local function evaluate(node)
    if node.type == "number" then
      -- Convert unit to pixels
      local value = node.value
      local unit = node.unit

      if unit == "px" then
        return value
      elseif unit == "%" then
        if not parentSize then
          if Calc._ErrorHandler then
            Calc._ErrorHandler:warn("Calc", "LAY_003", {
              unit = "%",
              issue = "parent dimension not available",
            })
          end
          return 0
        end
        return (value / 100) * parentSize
      elseif unit == "vw" then
        return (value / 100) * viewportWidth
      elseif unit == "vh" then
        return (value / 100) * viewportHeight
      else
        return 0
      end
    elseif node.type == "add" then
      return evaluate(node.left) + evaluate(node.right)
    elseif node.type == "subtract" then
      return evaluate(node.left) - evaluate(node.right)
    elseif node.type == "multiply" then
      return evaluate(node.left) * evaluate(node.right)
    elseif node.type == "divide" then
      local divisor = evaluate(node.right)
      if divisor == 0 then
        if Calc._ErrorHandler then
          Calc._ErrorHandler:warn("Calc", "VAL_006", {
            expression = calcObj._expr,
            error = "Division by zero",
          })
        end
        return 0
      end
      return evaluate(node.left) / divisor
    else
      return 0
    end
  end

  return evaluate(calcObj._ast)
end

return Calc
