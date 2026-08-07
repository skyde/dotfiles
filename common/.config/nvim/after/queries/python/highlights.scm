;; extends

;; Extra captures so Neovim can draw the distinctions VS Code's Python grammar
;; (MagicPython) makes. Colours live in lua/plugins/vscode-syntax.lua.
;;
;; Order matters: later patterns win, so the "demote" rules that reproduce
;; MagicPython's context rules come after the name lists they override.

;; ---------------------------------------------------------------------------
;; Definitions
;; ---------------------------------------------------------------------------

;; MagicPython classifies almost nothing in Python, so annotations stay plain
;; text; only a class definition's own name and its bases become a type colour.
(class_definition
  name: (identifier) @type.definition)

(class_definition
  superclasses: (argument_list (identifier) @type.definition))

;; `async def` is storage.type.function.async, unlike a bare `await`.
(function_definition
  "async" @keyword.function)

;; ---------------------------------------------------------------------------
;; MagicPython's name lists
;; ---------------------------------------------------------------------------

;; support.type.python -- built-in *types* are a different colour from built-in
;; functions. The grammar's rules all carry a (?<!\.) lookbehind, so a dotted
;; name never matches; `#not-has-parent? attribute` is that lookbehind.
((identifier) @type.builtin
  (#not-has-parent? @type.builtin attribute)
  (#any-of? @type.builtin
    "bool" "bytearray" "bytes" "classmethod" "complex" "dict" "float"
    "frozenset" "int" "list" "object" "property" "set" "slice"
    "staticmethod" "str" "tuple" "type" "super"))

;; support.type.exception.python -- same colour as the built-in types.
((identifier) @type.builtin
  (#not-has-parent? @type.builtin attribute)
  (#lua-match? @type.builtin "^[A-Z][A-Za-z]*Error$"))

((identifier) @type.builtin
  (#not-has-parent? @type.builtin attribute)
  (#lua-match? @type.builtin "^[A-Z][A-Za-z]*Warning$"))

((identifier) @type.builtin
  (#not-has-parent? @type.builtin attribute)
  (#any-of? @type.builtin
    "SystemExit" "StopIteration" "StopAsyncIteration" "KeyboardInterrupt"
    "GeneratorExit" "Exception" "BaseException"))

;; support.variable.magic.python -- dunder *variables*.
((identifier) @variable.magic
  (#any-of? @variable.magic
    "__all__" "__annotations__" "__bases__" "__builtins__" "__class__"
    "__classcell__" "__closure__" "__code__" "__debug__" "__defaults__"
    "__dict__" "__doc__" "__file__" "__func__" "__future__" "__globals__"
    "__kwdefaults__" "__match_args__" "__members__" "__metaclass__"
    "__methods__" "__module__" "__mro__" "__mro_entries__" "__name__"
    "__package__" "__path__" "__post_init__" "__qualname__" "__self__"
    "__signature__" "__slots__" "__spec__" "__subclasses__" "__traceback__"
    "__version__" "__weakref__" "__wrapped__"))

;; support.function.magic.python -- dunder *methods*. Unlike the lists above
;; this one has no (?<!\.) lookbehind, so `x.__len__()` counts too.
((identifier) @function.builtin
  (#any-of? @function.builtin
    "__abs__" "__add__" "__aenter__" "__aexit__" "__aiter__" "__and__"
    "__anext__" "__await__" "__bool__" "__bytes__" "__call__" "__ceil__"
    "__class_getitem__" "__cmp__" "__coerce__" "__complex__" "__contains__"
    "__copy__" "__deepcopy__" "__del__" "__delattr__" "__delete__"
    "__delitem__" "__delslice__" "__dir__" "__div__" "__divmod__" "__enter__"
    "__eq__" "__exit__" "__float__" "__floor__" "__floordiv__" "__format__"
    "__fspath__" "__ge__" "__get__" "__getattr__" "__getattribute__"
    "__getinitargs__" "__getitem__" "__getnewargs__" "__getslice__"
    "__getstate__" "__gt__" "__hash__" "__hex__" "__iadd__" "__iand__"
    "__idiv__" "__ifloordiv__" "__ilshift__" "__imatmul__" "__imod__"
    "__imul__" "__index__" "__init__" "__init_subclass__" "__instancecheck__"
    "__int__" "__invert__" "__ior__" "__ipow__" "__irshift__" "__isub__"
    "__iter__" "__itruediv__" "__ixor__" "__le__" "__len__" "__length_hint__"
    "__long__" "__lshift__" "__lt__" "__matmul__" "__missing__" "__mod__"
    "__mul__" "__ne__" "__neg__" "__new__" "__next__" "__nonzero__" "__oct__"
    "__or__" "__pos__" "__pow__" "__prepare__" "__radd__" "__rand__"
    "__rdiv__" "__rdivmod__" "__reduce__" "__reduce_ex__" "__repr__"
    "__reversed__" "__rfloordiv__" "__rlshift__" "__rmatmul__" "__rmod__"
    "__rmul__" "__ror__" "__round__" "__rpow__" "__rrshift__" "__rshift__"
    "__rsub__" "__rtruediv__" "__rxor__" "__set__" "__set_name__"
    "__setattr__" "__setitem__" "__setslice__" "__setstate__" "__sizeof__"
    "__str__" "__sub__" "__subclasscheck__" "__truediv__" "__trunc__"
    "__unicode__" "__xor__"))

;; ---------------------------------------------------------------------------
;; Structure, coloured the way C++ is
;; ---------------------------------------------------------------------------

;; A dotted name is never a built-in, matching the (?<!\.) lookbehind on
;; MagicPython's name lists -- `asyncio.TimeoutError` is an attribute, not the
;; exception type. Dunder methods are the exception: their rule has no
;; lookbehind, so `x.__len__()` stays coloured.
((attribute attribute: (identifier) @variable.member)
  (#not-lua-match? @variable.member "^__"))

;; ...but a method call is still a call. C++ colours `verts.size()` as a
;; function, and only `v.x` as a member, so re-promote the call form after the
;; demotion above.
(call
  function: (attribute attribute: (identifier) @function.method.call))

;; The object on the left of an attribute access, as in C++'s `obj.field`.
(attribute
  object: (identifier) @variable.object)

;; Call parentheses are their own colour in C++ (punctuation.section.arguments);
;; the parentheses of a `def` are not, matching a C++ parameter list.
(call
  arguments: (argument_list ["(" ")"] @punctuation.arguments))

;; `self` and `cls` are variable.language.special in an expression, the way
;; `this` is in C++. Placed after the object rule so `self.x` keeps this colour.
((identifier) @variable.builtin
  (#any-of? @variable.builtin "self" "cls"))

;; ...but plain parameters in a signature. This has to come last so it wins for
;; the `def f(self, ...)` position.
(parameters (identifier) @variable.parameter)
(parameters (typed_parameter (identifier) @variable.parameter))
(parameters (default_parameter name: (identifier) @variable.parameter))
(parameters (typed_default_parameter name: (identifier) @variable.parameter))
(lambda_parameters (identifier) @variable.parameter)

;; ---------------------------------------------------------------------------
;; Punctuation and keywords
;; ---------------------------------------------------------------------------

;; The return arrow and the decorator marker are punctuation in VS Code, not
;; operators.
(function_definition "->" @punctuation.delimiter)

;; The default rule paints the whole decorator, `@` included, at a raised
;; priority, so this one has to out-rank it.
((decorator "@" @punctuation.delimiter)
  (#set! priority 110))

;; `in` as part of a for header, and `del`, are control flow rather than
;; operators.
(for_statement "in" @keyword.repeat)
(for_in_clause "in" @keyword.repeat)
(delete_statement "del" @keyword)

;; Quotes are punctuation.definition.string, lighter than the string body -- but
;; only on a plain string. VS Code keeps the quotes of a prefixed string (f, r,
;; b, ...) the string colour, and the prefix letter sits in the same token as
;; the opening quote, so the pair is left alone entirely.
((string (string_start) @string.delimiter)
  (#lua-match? @string.delimiter "^[\"']"))

((string
  (string_start) @_start
  (string_end) @string.delimiter)
  (#lua-match? @_start "^[\"']"))
