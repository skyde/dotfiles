;; extends

;; Extra captures so Neovim can draw the distinctions the VS Code C++ grammar
;; (jeff-hykin.better-cpp-syntax) makes but nvim-treesitter's defaults do not.
;; Colours for these groups live in lua/plugins/vscode-syntax.lua.

;; Call parentheses are punctuation.section.arguments in VS Code, a colour of
;; their own. Grouping and parameter-list parens are not.
(call_expression
  function: [(identifier) (field_expression) (qualified_identifier)]
  arguments: (argument_list ["(" ")"] @punctuation.arguments))

(field_initializer
  (argument_list ["(" ")"] @punctuation.arguments))

;; A member-initialiser name reads as a call in VS Code
;; (entity.name.function.call.initializer).
(field_initializer
  (field_identifier) @function.call)

;; The object on the left of a member access: variable.other.object.
(field_expression
  argument: (identifier) @variable.object)

;; The variable a range-for declares is an object too
;; (variable.other.object.declare.for).
(for_range_loop
  declarator: (identifier) @variable.object)

(for_range_loop
  declarator: (reference_declarator (identifier) @variable.object))

(for_range_loop
  declarator: (pointer_declarator (identifier) @variable.object))

;; Access specifiers are storage.type.modifier.access, coloured like a type
;; rather than like `const`/`virtual`. Capturing the keyword token itself (not
;; the access_specifier node around it) is what overrides the default rule.
;; This covers both `public:` in a class body and `: public Base` in a base
;; clause, which the grammar represents with the same node.
(access_specifier ["public" "private" "protected"] @keyword.type)

;; A parameter written through a reference or pointer declarator is still a
;; parameter; the default queries only catch the plain-identifier form.
(parameter_declaration
  declarator: (reference_declarator (identifier) @variable.parameter))

(parameter_declaration
  declarator: (pointer_declarator (identifier) @variable.parameter))

(optional_parameter_declaration
  declarator: (reference_declarator (identifier) @variable.parameter))

(optional_parameter_declaration
  declarator: (pointer_declarator (identifier) @variable.parameter))

;; The named casts are keyword.operator.cast, coloured like a built-in type.
(template_function
  name: (identifier) @keyword.type
  (#any-of? @keyword.type "static_cast" "dynamic_cast" "const_cast" "reinterpret_cast"))

;; Their angle brackets are keyword.operator.comparison in VS Code, unlike the
;; angle brackets of any other template call, which stay punctuation.
((template_function
  name: (identifier) @_cast
  arguments: (template_argument_list ["<" ">"] @operator))
  (#any-of? @_cast "static_cast" "dynamic_cast" "const_cast" "reinterpret_cast"))

;; Anything left of a :: is entity.name.scope-resolution, a neutral grey, even
;; when the name looks like a type.
(qualified_identifier
  scope: (_) @module)

;; & and * in a declarator are storage.modifier.reference / .pointer.
(reference_declarator ["&" "&&"] @operator.reference)
(abstract_reference_declarator ["&" "&&"] @operator.reference)
(pointer_declarator "*" @operator.reference)
(abstract_pointer_declarator "*" @operator.reference)

;; Quotes are punctuation.definition.string, lighter than the string body.
(string_literal ["\"" ] @string.delimiter)
(char_literal ["'"] @string.delimiter)

;; The standard integral typedefs are storage.type.built-in in the VS Code
;; grammar, coloured like `int` rather than like a user-defined type.
((type_identifier) @type.builtin
  (#any-of? @type.builtin
    "int8_t" "int16_t" "int32_t" "int64_t" "uint8_t" "uint16_t" "uint32_t"
    "uint64_t" "int_fast8_t" "int_fast16_t" "int_fast32_t" "int_fast64_t"
    "uint_fast8_t" "uint_fast16_t" "uint_fast32_t" "uint_fast64_t"
    "int_least8_t" "int_least16_t" "int_least32_t" "int_least64_t"
    "uint_least8_t" "uint_least16_t" "uint_least32_t" "uint_least64_t"
    "intmax_t" "uintmax_t" "intptr_t" "uintptr_t" "size_t" "ssize_t"
    "ptrdiff_t" "time_t" "clock_t" "mode_t" "off_t" "pid_t" "uid_t" "gid_t"
    "ino_t" "dev_t" "key_t" "id_t" "div_t" "nlink_t" "blkcnt_t" "blksize_t"
    "useconds_t" "suseconds_t" "daddr_t" "caddr_t" "qaddr_t" "swblk_t"
    "segsz_t" "fixpt_t" "quad_t" "u_quad_t" "in_addr_t" "in_port_t"
    "u_char" "u_short" "u_int" "u_long" "ushort" "uint"
    "pthread_t" "pthread_attr_t" "pthread_cond_t" "pthread_condattr_t"
    "pthread_key_t" "pthread_mutex_t" "pthread_mutexattr_t" "pthread_once_t"
    "pthread_rwlock_t" "pthread_rwlockattr_t"))

;; `noexcept` is a storage.modifier like `const`, not an exception keyword.
["noexcept"] @keyword.modifier

;; `final` is storage.type.modifier, unlike `virtual`/`override`.
["final"] @keyword.type

;; `typedef`, `= default` and `= delete` land on the bare `keyword` rule, which
;; the user's overrides give a colour of its own.
["typedef"] @keyword.other
(default_method_clause "default" @keyword.other)
(delete_method_clause "delete" @keyword.other)

;; `default:` in a switch is control flow, unlike `= default` above.
(case_statement "default" @keyword.conditional)

;; An overloaded operator's name is keyword.other.operator.overload, the same
;; neutral grey as a reference or pointer marker. The inner tokens need
;; capturing too, or the default rule for `==` paints over this one.
(operator_name) @operator.reference
(operator_name _ @operator.reference)

;; The `~` of a destructor belongs to the function name.
(destructor_name) @function
(destructor_name "~" @function)

;; `mutable` on a lambda is a storage.modifier like anywhere else.
(lambda_specifier) @keyword.modifier

;; The angle brackets of a template *declaration* stay punctuation; only the
;; ones on a named cast become comparison operators (see above).
(template_parameter_list ["<" ">"] @punctuation.bracket)

;; An array member declaration is a declaration, not a property access.
(field_declaration
  declarator: (array_declarator declarator: (field_identifier) @variable.member))

;; `#pragma once` -- the pragma name is part of the directive. The argument of a
;; preprocessor call gets an injected parse, whose captures would otherwise win,
;; so this one is raised above them.
((preproc_call (preproc_arg) @keyword.directive)
  (#set! priority 130))

;; A trailing return type's arrow is punctuation, not an operator.
(trailing_return_type "->" @punctuation.delimiter)

;; `defined` in a preprocessor conditional is part of the directive.
(preproc_defined "defined" @keyword.directive)

;; [[attributes]]: the brackets are punctuation, the name is an entity.
(attribute_declaration ["[[" "]]"] @punctuation.bracket)
(attribute name: (identifier) @type)

;; A lambda capture is a parameter.
(lambda_capture_specifier (identifier) @variable.parameter)

;; A subscripted name, and any non-final link of a member-access chain, are
;; objects rather than plain variables or properties.
(subscript_expression
  argument: (identifier) @variable.object)

(field_expression
  argument: (field_expression field: (field_identifier) @variable.object))

;; better-cpp-syntax does not recognise a name introduced by `typedef`, leaving
;; it an ordinary variable (a `using` alias does become a type).
(type_definition
  declarator: (type_identifier) @variable)

;; The standard streams are plain variables in VS Code, not language constants.
((identifier) @variable
  (#any-of? @variable "stdin" "stdout" "stderr"))

;; `__VA_ARGS__` is part of the macro body (meta.preprocessor.macro).
((identifier) @module
  (#eq? @module "__VA_ARGS__"))
